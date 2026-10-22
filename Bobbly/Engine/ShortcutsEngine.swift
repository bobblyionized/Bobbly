//  ShortcutsEngine.swift
//  Bobbly/Engine — fallback engine (the "one sec" technique).
//
//  The user creates Shortcuts personal automations ("When Instagram is
//  opened/closed → Run Immediately") that call `LogAppEventIntent` and
//  `CheckAccessIntent`. If access is denied, the shortcut opens
//  `bobbly://gate?app=instagram`. Allowances live in the App Group store and
//  expire lazily: the next `CheckAccessIntent` after expiry returns false, so
//  no timer is needed to re-lock. Local notifications tell the user when an
//  unlock / emergency / study session ends (there is no monitor extension here).

import Foundation

@MainActor
final class ShortcutsEngine: BlockingEngine {
    let kind: EngineKind = .shortcuts

    let shared: SharedStore
    private let clock: () -> Date
    /// Tests set this to `false` to avoid touching UNUserNotificationCenter.
    var postsNotifications: Bool

    init(shared: SharedStore = .shared, clock: @escaping () -> Date = { Date() }, postsNotifications: Bool = true) {
        self.shared = shared
        self.clock = clock
        self.postsNotifications = postsNotifications
    }

    var status: EngineStatus {
        makeStatus(shared: shared, isReady: true, now: clock())
    }

    func activate() {
        if shared.engineKind == .familyControls {
            // Switching away from FamilyControls: never leave stale shields behind.
            ShieldPolicy.clearAll()
        }
        shared.engineKind = .shortcuts
        shared.pruneExpiredGrants(now: clock())
    }

    func block(_ list: BlockList) throws {
        shared.blockedAppKeys = list.appNames
    }

    @discardableResult
    func grantUnlocks(_ subjects: [UnlockSubject], displayName: String, minutes: Int) throws -> [ActiveUnlock] {
        let keys = subjects.compactMap(\.appKey)
        guard !subjects.isEmpty, keys.count == subjects.count else { throw EngineError.invalidSubject }

        let now = clock()
        let expires = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        var created: [ActiveUnlock] = []
        var seen = Set<String>()
        for subject in subjects {
            guard case .appName(let rawName) = subject else { continue }
            let key = AppKey.normalize(rawName)
            guard seen.insert(key).inserted else { continue }
            // Replace any existing grant for the same app.
            for existing in shared.grants where existing.appKey == key {
                revokeUnlock(id: existing.id)
            }
            let name = subjects.count == 1 ? displayName : (AppKey.isGroup(rawName) ? AppKey.groupDisplayName : rawName)
            let grant = UnlockGrant(appKey: key, tokenData: nil, displayName: name, grantedAt: now, expiresAt: expires)
            shared.addGrant(grant)
            if postsNotifications {
                BobblyNotifications.scheduleUnlockEnding(grantID: grant.id, appName: name, endsAt: expires, now: now)
                BobblyNotifications.postUnlockEnded(grantID: grant.id, appName: name, at: expires, now: now)
            }
            created.append(ActiveUnlock(grant: grant))
        }
        shared.incrementUnlocks(now: now)
        return created
    }

    func revokeUnlock(id: UUID) {
        shared.removeGrant(id: id)
        if postsNotifications {
            BobblyNotifications.cancel(ids: [BobblyNotifications.ID.unlockEnding(id), BobblyNotifications.ID.unlockEnded(id)])
        }
    }

    func emergencyUnblockAll(minutes: Int) throws {
        let now = clock()
        let until = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        shared.emergencyUntil = until
        if postsNotifications {
            BobblyNotifications.postEmergencyEnded(at: until, now: now)
        }
    }

    func endEmergency() {
        shared.emergencyUntil = nil
        if postsNotifications { BobblyNotifications.cancel(ids: [BobblyNotifications.ID.emergencyEnded]) }
    }

    func startStudy(_ study: ActiveStudy) throws {
        shared.activeStudy = study
        if postsNotifications, let end = study.endsAt {
            BobblyNotifications.postStudyEnded(whitelistName: study.whitelistName, at: end, now: clock())
        }
    }

    func endStudy() {
        shared.activeStudy = nil
        if postsNotifications { BobblyNotifications.cancel(ids: [BobblyNotifications.ID.studyEnded]) }
    }

    /// Sets the global "Bobbly off" flag so `CheckAccessIntent` always returns
    /// true. iOS doesn't let apps delete automations, so the report lists the
    /// manual steps.
    func detach() async -> DetachReport {
        if postsNotifications { BobblyNotifications.cancelAll() }
        if let study = shared.activeStudy { shared.recordStudyEnd(study, at: clock(), reason: .detached) }
        shared.isDetached = true
        shared.grants = []
        shared.activeStudy = nil
        shared.emergencyUntil = nil
        shared.pendingShieldRequest = nil
        return DetachReport(
            engine: .shortcuts,
            clearedShields: true,
            stoppedMonitoring: true,
            revokedAuthorization: false,
            manualSteps: ShortcutsEngine.manualDetachSteps,
            errors: []
        )
    }

    func reattach() {
        shared.isDetached = false
        activate()
    }

    func decision(forAppNamed appName: String, now: Date) -> AccessDecision {
        AccessPolicy.decide(appName: appName, snapshot: shared.accessSnapshot(), now: now)
    }

    static let manualDetachSteps: [String] = [
        "Bobbly is now off: every Bobbly check lets apps open.",
        "To remove the automations completely, open the Shortcuts app › Automation.",
        "Swipe left on each \"When … is opened/closed\" automation that runs Bobbly and tap Delete.",
        "Optional: delete Bobbly from your Home Screen to remove its Shortcuts actions.",
    ]
}
