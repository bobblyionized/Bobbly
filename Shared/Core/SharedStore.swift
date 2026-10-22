//  SharedStore.swift
//  Shared/Core — typed access to the App Group UserDefaults.
//
//  This is the ONLY state that extensions (shield config/action, monitor,
//  report) and App Intents read. SwiftData lives in the app process only.

import Foundation
import FamilyControls

final class SharedStore: @unchecked Sendable {
    static let shared = SharedStore(defaults: AppGroup.defaults)

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    enum Key: String, CaseIterable {
        case engineKind
        case isDetached
        case emergencyUntil
        case blockedSelection
        case blockedAppKeys
        case grants
        case activeStudy
        case pendingShieldRequest
        case counterDay
        case unlocksToday
        case interruptionsToday
        case companionMood
        case companionLives
        case dailyFreeUnlocks
        case lastShieldNotificationAt
        case reportSearchQuery
        case monitorLog
        case lastStudyEndedAt
        case lastShieldedApp
        case interruptionsByDay
        case lastShieldHitKey
        case lastShieldHitAt
        case tokensRevokedAt
        case studyEndRecords
        case importedInterruptionsByDay

        var name: String { "bobbly.shared." + rawValue }
    }

    // MARK: - Engine

    /// The engine the app last activated. Extensions use it to decide whether
    /// to touch ManagedSettings at all.
    var engineKind: EngineKind? {
        get { defaults.string(forKey: Key.engineKind.name).flatMap(EngineKind.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Key.engineKind.name) }
    }

    /// Global "Bobbly off" flag set by Emergency › Detach. When `true` every
    /// access check passes and no shield is applied.
    var isDetached: Bool {
        get { defaults.bool(forKey: Key.isDetached.name) }
        set { defaults.set(newValue, forKey: Key.isDetached.name) }
    }

    /// While in the future, everything is unblocked (Emergency unblock).
    var emergencyUntil: Date? {
        get { defaults.object(forKey: Key.emergencyUntil.name) as? Date }
        set { defaults.set(newValue, forKey: Key.emergencyUntil.name) }
    }

    func isEmergencyActive(at now: Date = Date()) -> Bool {
        guard let until = emergencyUntil else { return false }
        return until > now
    }

    // MARK: - Block lists

    /// FamilyControls engine: apps / categories / sites the user chose to block.
    var blockedSelection: FamilyActivitySelection {
        get { TokenCoding.decode(FamilyActivitySelection.self, from: defaults.data(forKey: Key.blockedSelection.name)) ?? FamilyActivitySelection() }
        set { defaults.set(TokenCoding.encode(newValue), forKey: Key.blockedSelection.name) }
    }

    /// Shortcuts engine: normalized names of blocked apps (see `AppKey`).
    var blockedAppKeys: [String] {
        get { defaults.stringArray(forKey: Key.blockedAppKeys.name) ?? [] }
        set { defaults.set(Array(Set(newValue.map(AppKey.normalize))).sorted(), forKey: Key.blockedAppKeys.name) }
    }

    // MARK: - Unlock grants

    var grants: [UnlockGrant] {
        get { TokenCoding.decode([UnlockGrant].self, from: defaults.data(forKey: Key.grants.name)) ?? [] }
        set { defaults.set(TokenCoding.encode(newValue), forKey: Key.grants.name) }
    }

    func activeGrants(at now: Date = Date()) -> [UnlockGrant] {
        grants.filter { $0.isActive(at: now) }
    }

    func addGrant(_ grant: UnlockGrant) {
        var all = grants
        all.removeAll { $0.id == grant.id }
        all.append(grant)
        grants = all
    }

    func removeGrant(id: UUID) {
        grants = grants.filter { $0.id != id }
    }

    /// Removes expired grants and returns the ones removed.
    @discardableResult
    func pruneExpiredGrants(now: Date = Date()) -> [UnlockGrant] {
        let all = grants
        let expired = all.filter { !$0.isActive(at: now) }
        if !expired.isEmpty { grants = all.filter { $0.isActive(at: now) } }
        return expired
    }

    // MARK: - Study

    var activeStudy: ActiveStudy? {
        get { TokenCoding.decode(ActiveStudy.self, from: defaults.data(forKey: Key.activeStudy.name)) }
        set { defaults.set(newValue.flatMap { TokenCoding.encode($0) }, forKey: Key.activeStudy.name) }
    }

    /// Set by the monitor when a timed study session ends while the app is closed,
    /// so the app can credit focus time on next launch.
    var lastStudyEndedAt: Date? {
        get { defaults.object(forKey: Key.lastStudyEndedAt.name) as? Date }
        set { defaults.set(newValue, forKey: Key.lastStudyEndedAt.name) }
    }

    // MARK: - Shield hand-off

    var pendingShieldRequest: PendingShieldRequest? {
        get { TokenCoding.decode(PendingShieldRequest.self, from: defaults.data(forKey: Key.pendingShieldRequest.name)) }
        set { defaults.set(newValue.flatMap { TokenCoding.encode($0) }, forKey: Key.pendingShieldRequest.name) }
    }

    /// Best effort: the shield-configuration extension records the display name
    /// of the app it last shielded, so the shield-action extension (which only
    /// gets a token) can name it in the "Talk to Bobbly" notification.
    var lastShieldedApp: ShieldedAppName? {
        get { TokenCoding.decode(ShieldedAppName.self, from: defaults.data(forKey: Key.lastShieldedApp.name)) }
        set { defaults.set(newValue.flatMap { TokenCoding.encode($0) }, forKey: Key.lastShieldedApp.name) }
    }

    var lastShieldNotificationAt: Date? {
        get { defaults.object(forKey: Key.lastShieldNotificationAt.name) as? Date }
        set { defaults.set(newValue, forKey: Key.lastShieldNotificationAt.name) }
    }

    // MARK: - Daily counters (reset automatically when the day changes)

    func unlocksToday(now: Date = Date()) -> Int { counter(.unlocksToday, now: now) }
    func incrementUnlocks(now: Date = Date()) { increment(.unlocksToday, now: now) }

    // MARK: - Shield interruptions (kept per day so days the app wasn't opened aren't lost)

    /// Days kept in `interruptionsByDay`.
    static let interruptionHistoryDays = 60
    /// Two shield hits on the same app within this window are one attempt.
    static let shieldHitDedupWindow: TimeInterval = 120

    /// Stable key for a day: start-of-day Unix time as a string.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        String(Int(calendar.startOfDay(for: date).timeIntervalSince1970))
    }

    /// Shield interruptions per day (`dayKey` → count), recorded by the shield-action extension.
    var interruptionsByDay: [String: Int] {
        get { (defaults.dictionary(forKey: Key.interruptionsByDay.name) as? [String: Int]) ?? [:] }
        set { defaults.set(newValue, forKey: Key.interruptionsByDay.name) }
    }

    func interruptionsToday(now: Date = Date()) -> Int {
        interruptionsByDay[Self.dayKey(now)] ?? 0
    }

    /// App-only bookkeeping: per-day counts already copied into SwiftData.
    var importedInterruptionsByDay: [String: Int] {
        get { (defaults.dictionary(forKey: Key.importedInterruptionsByDay.name) as? [String: Int]) ?? [:] }
        set { defaults.set(newValue, forKey: Key.importedInterruptionsByDay.name) }
    }

    func incrementInterruptions(now: Date = Date()) {
        var map = interruptionsByDay
        map[Self.dayKey(now), default: 0] += 1
        let oldest = now.addingTimeInterval(-Double(Self.interruptionHistoryDays) * 86_400).timeIntervalSince1970
        map = map.filter { (Double($0.key) ?? 0) >= oldest }
        interruptionsByDay = map
    }

    /// Counts one shield interruption for `attemptKey` (an encoded token),
    /// ignoring repeat hits on the same app within `shieldHitDedupWindow`
    /// (e.g. "Talk to Bobbly" then "Go back" on the same shield).
    /// - Returns: `true` if it was counted.
    @discardableResult
    func recordShieldInterruption(attemptKey: String, now: Date = Date()) -> Bool {
        if defaults.string(forKey: Key.lastShieldHitKey.name) == attemptKey,
           let last = defaults.object(forKey: Key.lastShieldHitAt.name) as? Date,
           now.timeIntervalSince(last) < Self.shieldHitDedupWindow, now >= last {
            defaults.set(now, forKey: Key.lastShieldHitAt.name)
            return false
        }
        defaults.set(attemptKey, forKey: Key.lastShieldHitKey.name)
        defaults.set(now, forKey: Key.lastShieldHitAt.name)
        incrementInterruptions(now: now)
        return true
    }

    private func dayStamp(_ date: Date) -> Double {
        Calendar.current.startOfDay(for: date).timeIntervalSince1970
    }

    private func rollDayIfNeeded(now: Date) {
        let today = dayStamp(now)
        if defaults.double(forKey: Key.counterDay.name) != today {
            defaults.set(today, forKey: Key.counterDay.name)
            defaults.set(0, forKey: Key.unlocksToday.name)
        }
    }

    // MARK: - Token invalidation

    /// Set when Screen Time authorization was revoked (detach, or the user
    /// turned it off in Settings). Every token saved before it is void: the
    /// block list is cleared and whitelists must be re-picked.
    var tokensRevokedAt: Date? {
        get { defaults.object(forKey: Key.tokensRevokedAt.name) as? Date }
        set { defaults.set(newValue, forKey: Key.tokensRevokedAt.name) }
    }

    /// Clears every saved FamilyControls token and records the revocation.
    func invalidateTokens(now: Date = Date()) {
        blockedSelection = FamilyActivitySelection()
        grants = grants.filter { $0.tokenData == nil }
        if let study = activeStudy {
            // Its whitelist tokens are void; never keep shielding "everything except nothing".
            recordStudyEnd(study, at: now, reason: .detached)
            activeStudy = nil
        }
        tokensRevokedAt = now
    }

    // MARK: - Study end records

    /// Why/when recent study sessions ended (newest last, max 10). Lets the app
    /// close its SwiftData session correctly even if the end happened elsewhere
    /// (monitor extension, Siri detach).
    var studyEndRecords: [StudyEndRecord] {
        get { TokenCoding.decode([StudyEndRecord].self, from: defaults.data(forKey: Key.studyEndRecords.name)) ?? [] }
        set { defaults.set(TokenCoding.encode(Array(newValue.suffix(10))), forKey: Key.studyEndRecords.name) }
    }

    func recordStudyEnd(_ study: ActiveStudy, at date: Date, reason: StudyEndRecord.Reason) {
        lastStudyEndedAt = date
        var records = studyEndRecords.filter { $0.sessionID != study.sessionID }
        records.append(StudyEndRecord(sessionID: study.sessionID, endedAt: date, reason: reason))
        studyEndRecords = records
    }

    func studyEndRecord(for sessionID: UUID) -> StudyEndRecord? {
        studyEndRecords.last { $0.sessionID == sessionID }
    }

    private func counter(_ key: Key, now: Date) -> Int {
        guard defaults.double(forKey: Key.counterDay.name) == dayStamp(now) else { return 0 }
        return defaults.integer(forKey: key.name)
    }

    private func increment(_ key: Key, now: Date) {
        rollDayIfNeeded(now: now)
        defaults.set(defaults.integer(forKey: key.name) + 1, forKey: key.name)
    }

    // MARK: - Companion mirror (read by the shield to personalize its text)

    var companionMood: Int {
        get { defaults.object(forKey: Key.companionMood.name) as? Int ?? 60 }
        set { defaults.set(newValue, forKey: Key.companionMood.name) }
    }

    var companionLives: Int {
        get { defaults.object(forKey: Key.companionLives.name) as? Int ?? 3 }
        set { defaults.set(newValue, forKey: Key.companionLives.name) }
    }

    /// Unlocks per day that do not cost Bobbly a life.
    var dailyFreeUnlocks: Int {
        get { defaults.object(forKey: Key.dailyFreeUnlocks.name) as? Int ?? 3 }
        set { defaults.set(max(0, newValue), forKey: Key.dailyFreeUnlocks.name) }
    }

    // MARK: - Report search (best effort: read by the report extension)

    var reportSearchQuery: String {
        get { defaults.string(forKey: Key.reportSearchQuery.name) ?? "" }
        set { defaults.set(newValue, forKey: Key.reportSearchQuery.name) }
    }

    // MARK: - Diagnostics log (ring buffer, newest last)

    var monitorLog: [String] {
        defaults.stringArray(forKey: Key.monitorLog.name) ?? []
    }

    func appendLog(_ line: String, now: Date = Date()) {
        let stamp = ISO8601DateFormatter().string(from: now)
        var log = monitorLog
        log.append("\(stamp) \(line)")
        if log.count > 40 { log.removeFirst(log.count - 40) }
        defaults.set(log, forKey: Key.monitorLog.name)
    }

    // MARK: - Snapshot for pure policy evaluation

    func accessSnapshot() -> AccessSnapshot {
        AccessSnapshot(
            isDetached: isDetached,
            emergencyUntil: emergencyUntil,
            blockedAppKeys: Set(blockedAppKeys),
            grants: grants,
            study: activeStudy
        )
    }

    /// Wipes every Bobbly key (used by tests and "Reset Bobbly").
    func resetAll() {
        for key in Key.allCases { defaults.removeObject(forKey: key.name) }
    }
}
