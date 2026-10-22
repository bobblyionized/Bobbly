//  FamilyControlsEngine.swift
//  Bobbly/Engine — primary engine: ManagedSettings shields + DeviceActivity.
//
//  All shields are derived by `ShieldPolicy.reconcile` from `SharedStore`.
//  Every timed state (unlock, emergency, study) also gets a one-shot
//  DeviceActivity *trigger* whose interval STARTS at the moment the state
//  ends; the monitor extension reconciles in `intervalDidStart`, which is how
//  apps re-lock while Bobbly is closed. The app also reconciles on every
//  foreground as a safety net.

import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class FamilyControlsEngine: BlockingEngine {
    let kind: EngineKind = .familyControls

    let shared: SharedStore
    private let center = DeviceActivityCenter()
    private let clock: () -> Date

    /// Last non-fatal monitoring error (shown in Settings diagnostics).
    private(set) var lastMonitoringError: String?

    init(shared: SharedStore = .shared, clock: @escaping () -> Date = { Date() }) {
        self.shared = shared
        self.clock = clock
    }

    // MARK: Authorization

    var authorizationStatus: AuthorizationStatus {
        AuthorizationCenter.shared.authorizationStatus
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    /// Shows the system Screen Time prompt (individual / self-control mode).
    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    // MARK: BlockingEngine

    var status: EngineStatus {
        makeStatus(shared: shared, isReady: isAuthorized, now: clock())
    }

    /// Names of DeviceActivity schedules currently registered (diagnostics).
    var monitoredActivityNames: [String] {
        center.activities.map(\.rawValue).sorted()
    }

    func activate() {
        shared.engineKind = .familyControls
        if !center.activities.contains(.bobblyDaily) {
            startMonitoring(.bobblyDaily, schedule: ActivitySchedules.daily)
        }
        reconcile()
        rescheduleTriggers()
    }

    func block(_ list: BlockList) throws {
        guard isAuthorized else { throw EngineError.notAuthorized }
        shared.blockedSelection = list.selection
        reconcile()
    }

    @discardableResult
    func grantUnlocks(_ subjects: [UnlockSubject], displayName: String, minutes: Int) throws -> [ActiveUnlock] {
        guard !subjects.isEmpty, !subjects.contains(.studySession) else { throw EngineError.invalidSubject }
        let now = clock()
        let expires = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))

        var grants: [UnlockGrant] = []
        for subject in subjects {
            switch subject {
            case .application(let token):
                // Replace an existing grant for the same token.
                for existing in shared.grants where existing.applicationToken == token {
                    removeGrantAndTrigger(existing.id)
                }
                grants.append(UnlockGrant(appKey: nil, tokenData: TokenCoding.encode(token),
                                          displayName: subjects.count == 1 ? displayName : "Selected app",
                                          grantedAt: now, expiresAt: expires))
            case .appName(let name):
                // A Shortcuts automation can still call in while this engine runs.
                let key = AppKey.normalize(name)
                for existing in shared.grants where existing.appKey == key {
                    removeGrantAndTrigger(existing.id)
                }
                grants.append(UnlockGrant(appKey: key, tokenData: nil,
                                          displayName: subjects.count == 1 ? displayName : name,
                                          grantedAt: now, expiresAt: expires))
            case .studySession:
                break
            }
        }

        for grant in grants { shared.addGrant(grant) }
        shared.incrementUnlocks(now: now)
        reconcile()
        // One trigger per expiry time covers the whole batch (the monitor
        // re-locks every grant that is due), keeping well under the
        // ~20-activity limit even for multi-app unlocks.
        rescheduleTriggers()
        if let first = grants.first {
            let name = grants.count == 1 ? first.displayName : "\(grants.count) apps"
            BobblyNotifications.scheduleUnlockEnding(grantID: first.id, appName: name, endsAt: expires, now: now)
        }
        return grants.map(ActiveUnlock.init(grant:))
    }

    func revokeUnlock(id: UUID) {
        removeGrantAndTrigger(id)
        reconcile()
        rescheduleTriggers()
    }

    func emergencyUnblockAll(minutes: Int) throws {
        let now = clock()
        let until = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        shared.emergencyUntil = until
        reconcile()
        scheduleTrigger(.bobblyEmergency, at: until, now: now)
    }

    func endEmergency() {
        shared.emergencyUntil = nil
        center.stopMonitoring([.bobblyEmergency])
        reconcile()
    }

    func startStudy(_ study: ActiveStudy) throws {
        guard isAuthorized else { throw EngineError.notAuthorized }
        shared.activeStudy = study
        reconcile()
        center.stopMonitoring([.bobblyStudy])
        if let end = study.endsAt {
            scheduleTrigger(.bobblyStudy, at: end, now: clock())
        }
    }

    func endStudy() {
        shared.activeStudy = nil
        center.stopMonitoring([.bobblyStudy])
        reconcile()
    }

    /// Clears every store, stops every DeviceActivity schedule and revokes
    /// Screen Time authorization, so Bobbly disappears from
    /// Settings › Screen Time › Apps with Screen Time Access.
    func detach() async -> DetachReport {
        var errors: [String] = []
        let pendingIDs = shared.grants.map { BobblyNotifications.ID.unlockEnding($0.id) }
        BobblyNotifications.cancel(ids: pendingIDs)

        shared.isDetached = true
        shared.grants = []
        shared.activeStudy = nil
        shared.emergencyUntil = nil

        ShieldPolicy.clearAll()
        center.stopMonitoring()

        var revoked = false
        do {
            try await revokeAuthorization()
            revoked = true
        } catch {
            errors.append("Revoking Screen Time access failed: \(error.localizedDescription)")
        }
        shared.appendLog("detach: shields cleared, monitoring stopped, revoked=\(revoked)")

        var steps = ["All Bobbly shields are removed and monitoring is stopped."]
        if revoked {
            steps.append("Bobbly no longer has Screen Time access.")
        } else {
            steps.append("Open Settings › Screen Time › Apps with Screen Time Access and turn Bobbly off.")
        }
        steps.append("If you also set up Shortcuts automations, delete them in Shortcuts › Automation.")

        return DetachReport(engine: .familyControls, clearedShields: true, stoppedMonitoring: true,
                            revokedAuthorization: revoked, manualSteps: steps, errors: errors)
    }

    func reattach() {
        shared.isDetached = false
        if isAuthorized { activate() }
    }

    func decision(forAppNamed appName: String, now: Date) -> AccessDecision {
        AccessPolicy.decide(appName: appName, snapshot: shared.accessSnapshot(), now: now)
    }

    // MARK: Helpers

    /// Re-derives shields from SharedStore (cheap; call after every change).
    func reconcile() {
        let summary = ShieldPolicy.reconcile(shared: shared, now: clock())
        shared.appendLog("app reconcile: \(summary)")
    }

    /// Makes sure every running timed state has a trigger and no stale
    /// triggers remain (DeviceActivity allows only ~20 activities).
    func rescheduleTriggers() {
        let now = clock()
        let active = shared.activeGrants(at: now)
        let activeGrantIDs = Set(active.map(\.id))
        var registered = center.activities

        // Drop triggers whose grant is gone.
        let stale = registered.filter { name in
            guard let id = name.bobblyUnlockGrantID else { return false }
            return !activeGrantIDs.contains(id)
        }
        if !stale.isEmpty {
            center.stopMonitoring(stale)
            registered.removeAll { stale.contains($0) }
        }

        // Every distinct expiry needs one trigger (named after one of its grants).
        let byExpiry = Dictionary(grouping: active, by: \.expiresAt)
        for (expiry, group) in byExpiry {
            let covered = group.contains { registered.contains(.bobblyUnlock($0.id)) }
            if !covered, let first = group.first {
                scheduleTrigger(.bobblyUnlock(first.id), at: expiry, now: now)
            }
        }
        if let until = shared.emergencyUntil, until > now, !registered.contains(.bobblyEmergency) {
            scheduleTrigger(.bobblyEmergency, at: until, now: now)
        }
        if let end = shared.activeStudy?.endsAt, end > now, !registered.contains(.bobblyStudy) {
            scheduleTrigger(.bobblyStudy, at: end, now: now)
        }
    }

    private func removeGrantAndTrigger(_ id: UUID) {
        shared.removeGrant(id: id)
        center.stopMonitoring([.bobblyUnlock(id)])
        BobblyNotifications.cancel(ids: [BobblyNotifications.ID.unlockEnding(id)])
    }

    private func scheduleTrigger(_ name: DeviceActivityName, at date: Date, now: Date) {
        let when = ActivitySchedules.triggerDate(for: date, now: now)
        startMonitoring(name, schedule: ActivitySchedules.trigger(at: when))
    }

    private func startMonitoring(_ name: DeviceActivityName, schedule: DeviceActivitySchedule) {
        do {
            center.stopMonitoring([name])
            try center.startMonitoring(name, during: schedule)
            lastMonitoringError = nil
        } catch {
            // Non-fatal: the app also reconciles on every foreground, so a
            // missed schedule only delays re-locking until Bobbly is opened.
            lastMonitoringError = "\(name.rawValue): \(error.localizedDescription)"
            shared.appendLog("startMonitoring failed \(lastMonitoringError ?? "")")
        }
    }

    private func revokeAuthorization() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            AuthorizationCenter.shared.revokeAuthorization { result in
                continuation.resume(with: result)
            }
        }
    }
}
