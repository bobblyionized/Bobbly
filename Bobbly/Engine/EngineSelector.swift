//  EngineSelector.swift
//  Bobbly/Engine — decides which engine runs and is the single entry point
//  ViewModels use to change blocking state (so `status` always refreshes).
//
//  Policy:
//   • Detached → nothing is enforced until the user re-attaches.
//   • Screen Time authorization approved → FamilyControls engine.
//   • Authorization denied / throws (e.g. signer dropped the entitlement)
//     → Shortcuts engine, with the reason shown in Settings diagnostics.
//   • Not determined yet (before tutorial step 2) → `.undetermined`
//     (the Shortcuts engine object answers queries meanwhile; nothing is blocked).

import Foundation
import Observation
import FamilyControls

enum EngineSelectionState: Equatable {
    /// Screen Time access has not been requested yet.
    case undetermined
    /// Real blocking is running.
    case familyControls
    /// Fallback is running; `reason` explains why FamilyControls isn't.
    case shortcutsFallback(reason: String)
    /// Emergency detach is in effect; nothing is enforced.
    case detached

    var label: String {
        switch self {
        case .undetermined: return "Not set up yet"
        case .familyControls: return "Screen Time (FamilyControls)"
        case .shortcutsFallback: return "Shortcuts fallback"
        case .detached: return "Detached (Bobbly off)"
        }
    }
}

/// Settings › Diagnostics.
struct EngineDiagnostics: Equatable {
    var activeEngine: EngineKind
    var selectionState: EngineSelectionState
    /// "approved" / "denied" / "notDetermined".
    var authorizationStatus: String
    var lastAuthorizationError: String?
    var lastMonitoringError: String?
    /// `false` = the signer dropped the App Group entitlement; extensions can't see Bobbly's state.
    var appGroupAvailable: Bool
    var usingFallbackDataStore: Bool
    var monitoredActivities: [String]
    /// Newest last; written by the app and the monitor extension.
    var recentLog: [String]

    static let placeholder = EngineDiagnostics(activeEngine: .shortcuts, selectionState: .undetermined,
                                               authorizationStatus: "notDetermined", lastAuthorizationError: nil,
                                               lastMonitoringError: nil, appGroupAvailable: true,
                                               usingFallbackDataStore: false, monitoredActivities: [], recentLog: [])
}

@Observable
@MainActor
final class EngineSelector {
    private(set) var state: EngineSelectionState = .undetermined
    private(set) var status: EngineStatus = .placeholder
    private(set) var diagnostics: EngineDiagnostics = .placeholder
    private(set) var isRequestingAuthorization = false
    private(set) var lastAuthorizationError: String?

    let familyControls: FamilyControlsEngine
    let shortcuts: ShortcutsEngine
    let shared: SharedStore

    init(shared: SharedStore = .shared) {
        self.shared = shared
        self.familyControls = FamilyControlsEngine(shared: shared)
        self.shortcuts = ShortcutsEngine(shared: shared)
    }

    /// The engine currently enforcing blocks.
    var active: any BlockingEngine {
        if state == .familyControls { return familyControls }
        return shortcuts
    }

    var kind: EngineKind { active.kind }

    // MARK: - Selection

    /// Call at launch and whenever the app becomes active.
    /// - Parameter requestIfNeeded: show the Screen Time prompt if not determined yet.
    func bootstrap(requestIfNeeded: Bool) async {
        if shared.isDetached {
            state = .detached
            refresh()
            return
        }
        if prefersShortcuts {
            select(.shortcutsFallback(reason: "Chosen in Settings."))
            return
        }
        switch familyControls.authorizationStatus {
        case .approved:
            select(.familyControls)
        case .denied:
            select(.shortcutsFallback(reason: "Screen Time access was denied."))
        case .notDetermined:
            if requestIfNeeded {
                await requestFamilyControls()
            } else if case .shortcutsFallback = state {
                refresh() // keep the fallback chosen earlier this session
            } else {
                state = .undetermined
                refresh()
            }
        @unknown default:
            select(.shortcutsFallback(reason: "Unknown Screen Time authorization state."))
        }
    }

    /// Shows the Screen Time prompt. On failure, falls back to Shortcuts.
    /// - Returns: `true` if FamilyControls is now active.
    @discardableResult
    func requestFamilyControls() async -> Bool {
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        prefersShortcuts = false
        do {
            try await familyControls.requestAuthorization()
            lastAuthorizationError = nil
            if shared.isDetached { shared.isDetached = false }
            select(.familyControls)
            return true
        } catch {
            lastAuthorizationError = String(describing: error)
            shared.appendLog("Screen Time authorization failed: \(error)")
            select(.shortcutsFallback(reason: "Screen Time access failed: \(error.localizedDescription)"))
            return false
        }
    }

    /// Manually switch to the Shortcuts fallback (Settings). Persists until
    /// "Retry Screen Time access" (`requestFamilyControls()`).
    func useShortcutsFallback(reason: String = "Chosen in Settings.") {
        prefersShortcuts = true
        select(.shortcutsFallback(reason: reason))
    }

    private static let prefersShortcutsKey = "bobbly.engine.prefersShortcuts"

    private var prefersShortcuts: Bool {
        get { UserDefaults.standard.bool(forKey: Self.prefersShortcutsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.prefersShortcutsKey) }
    }

    private func select(_ newState: EngineSelectionState) {
        state = newState
        active.activate()
        refresh()
    }

    /// Re-reads status + diagnostics. Cheap; call after anything changes.
    func refresh() {
        status = active.status
        diagnostics = EngineDiagnostics(
            activeEngine: active.kind,
            selectionState: state,
            authorizationStatus: Self.describe(familyControls.authorizationStatus),
            lastAuthorizationError: lastAuthorizationError,
            lastMonitoringError: familyControls.lastMonitoringError,
            appGroupAvailable: AppGroup.isContainerAvailable,
            usingFallbackDataStore: BobblyModelContainer.isUsingFallbackStore,
            monitoredActivities: state == .familyControls ? familyControls.monitoredActivityNames : [],
            recentLog: Array(shared.monitorLog.suffix(15))
        )
    }

    private static func describe(_ status: AuthorizationStatus) -> String {
        switch status {
        case .approved: return "approved"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Operations (always go through these so `status` stays fresh)

    func updateBlockList(_ list: BlockList) throws {
        defer { refresh() }
        // Keep both vocabularies in sync so switching engines keeps the list.
        shared.blockedAppKeys = list.appNames
        shared.blockedSelection = list.selection
        try active.block(list)
    }

    @discardableResult
    func grantUnlock(_ subject: UnlockSubject, displayName: String, minutes: Int) throws -> ActiveUnlock {
        defer { refresh() }
        return try active.grantUnlock(subject, displayName: displayName, minutes: minutes)
    }

    /// Several apps, one unlock (counts once toward today's unlocks).
    @discardableResult
    func grantUnlocks(_ subjects: [UnlockSubject], displayName: String, minutes: Int) throws -> [ActiveUnlock] {
        defer { refresh() }
        return try active.grantUnlocks(subjects, displayName: displayName, minutes: minutes)
    }

    func revokeUnlock(id: UUID) {
        active.revokeUnlock(id: id)
        refresh()
    }

    func emergencyUnblockAll(minutes: Int) throws {
        defer { refresh() }
        try active.emergencyUnblockAll(minutes: minutes)
    }

    func endEmergency() {
        active.endEmergency()
        refresh()
    }

    func startStudy(_ study: ActiveStudy) throws {
        defer { refresh() }
        try active.startStudy(study)
    }

    func endStudy() {
        active.endStudy()
        refresh()
    }

    /// Emergency detach. If Screen Time access exists at all, the
    /// FamilyControls detach runs (clear stores, stop monitoring, revoke);
    /// both engines share the "Bobbly off" flag, so Shortcuts checks pass too.
    func detach() async -> DetachReport {
        let report: DetachReport
        if state == .familyControls || familyControls.isAuthorized {
            report = await familyControls.detach()
        } else {
            report = await shortcuts.detach()
        }
        state = .detached
        refresh()
        return report
    }

    /// Re-applies shields from SharedStore (call when the app becomes active,
    /// in case a monitor callback was missed).
    func reconcileNow() {
        if state == .familyControls {
            familyControls.reconcile()
            familyControls.rescheduleTriggers()
        } else {
            shared.pruneExpiredGrants()
        }
        refresh()
    }

    /// Turns Bobbly back on. FamilyControls asks for authorization again if needed.
    func reattach() async {
        shared.isDetached = false
        state = .undetermined
        await bootstrap(requestIfNeeded: true)
    }

    /// Access decision for a named app (used by intents and the Gate).
    func decision(forAppNamed appName: String, now: Date = Date()) -> AccessDecision {
        active.decision(forAppNamed: appName, now: now)
    }
}
