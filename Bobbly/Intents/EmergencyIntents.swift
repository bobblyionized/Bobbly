//  EmergencyIntents.swift
//  Bobbly/Intents — Siri/Shortcuts escape hatches that work even if the app UI
//  is broken: "Bobbly emergency" (unblock everything) and "Detach Bobbly".

import AppIntents
import Foundation

/// "Hey Siri, Bobbly emergency" — free emergency unblock of everything.
struct EmergencyUnblockIntent: AppIntent {
    static var title: LocalizedStringResource = "Emergency Unblock"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Minutes", default: 30)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Unblock everything for \(\.$minutes) minutes")
    }

    init() {}

    init(minutes: Int) {
        self.minutes = minutes
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let shared = SharedStore.shared
        let clamped = min(240, max(5, minutes))
        let engine: any BlockingEngine
        if shared.engineKind == .familyControls {
            engine = FamilyControlsEngine(shared: shared)
        } else {
            engine = ShortcutsEngine(shared: shared)
        }
        try engine.emergencyUnblockAll(minutes: clamped)
        UsageTracker(context: BobblyModelContainer.shared.mainContext)
            .logUnlock(appName: "Everything", appKey: nil, reason: "Siri emergency", category: "emergency",
                       minutes: clamped, granted: true, isEmergency: true)
        NotificationCenter.default.post(name: .bobblySharedStateChanged, object: nil)
        return .result(dialog: "Everything is unblocked for \(clamped) minutes. Take care of yourself.")
    }
}

/// "Hey Siri, detach Bobbly" — removes all shields/monitoring and turns Bobbly off.
struct DetachBobblyIntent: AppIntent {
    static var title: LocalizedStringResource = "Detach Bobbly"
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let shared = SharedStore.shared
        // Same rule as the in-app Emergency screen (EngineSelector.detach).
        let report = await DetachRule.detach(shared: shared,
                                             familyControls: FamilyControlsEngine(shared: shared),
                                             shortcuts: ShortcutsEngine(shared: shared))
        // The engines recorded a `.detached` StudyEndRecord for any running
        // study; StudyViewModel.syncWithEngine closes the SwiftData session
        // (ended early, no bonus) when the app observes this change.
        NotificationCenter.default.post(name: .bobblySharedStateChanged, object: nil)
        let summary = report.revokedAuthorization
            ? "Bobbly is detached and no longer has Screen Time access."
            : "Bobbly is off. Open Bobbly › Emergency for the remaining steps."
        return .result(dialog: "\(summary)")
    }
}
