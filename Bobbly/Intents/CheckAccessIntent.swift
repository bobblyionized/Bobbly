//  CheckAccessIntent.swift
//  Bobbly/Intents — "Check Access in Bobbly" Shortcuts action.
//
//  Used in a "When <App> is opened" personal automation. Returns `false` when
//  the app is blocked; the shortcut then opens bobbly://gate?app=<App>.

import AppIntents
import Foundation

struct CheckAccessIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Access"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App")
    var app: String

    static var parameterSummary: some ParameterSummary {
        Summary("Check if Bobbly allows opening \(\.$app)")
    }

    init() {}

    init(app: String) {
        self.app = app
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let shared = SharedStore.shared
        let decision = AccessPolicy.decide(appName: app, snapshot: shared.accessSnapshot(), now: Date())
        if !decision.isAllowed {
            // One attempt = one interruption. The Gate this shortcut opens next
            // uses logInterruptionIfNew, so it won't count the same attempt again.
            // (SharedStore's per-day counts are shield hits only.)
            UsageTracker(context: BobblyModelContainer.shared.mainContext)
                .logInterruption(appName: app, source: .checkAccess)
        }
        NotificationCenter.default.post(name: .bobblySharedStateChanged, object: nil)
        return .result(value: decision.isAllowed)
    }
}
