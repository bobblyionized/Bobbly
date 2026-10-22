//  LogAppEventIntent.swift
//  Bobbly/Intents — "Log App Event in Bobbly" Shortcuts action.
//
//  Called by "When <App> is opened / is closed" automations; builds the
//  UsageSession history the tracker, Stats and Search use (Shortcuts engine).

import AppIntents
import Foundation

enum AppEventKind: String, AppEnum {
    case opened
    case closed

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "App Event"
    static var caseDisplayRepresentations: [AppEventKind: DisplayRepresentation] = [
        .opened: "Opened",
        .closed: "Closed",
    ]
}

struct LogAppEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Log App Event"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App")
    var app: String

    @Parameter(title: "Event", default: .opened)
    var event: AppEventKind

    static var parameterSummary: some ParameterSummary {
        Summary("Log that \(\.$app) was \(\.$event)")
    }

    init() {}

    init(app: String, event: AppEventKind) {
        self.app = app
        self.event = event
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let tracker = UsageTracker(context: BobblyModelContainer.shared.mainContext)
        switch event {
        case .opened: tracker.logOpened(appName: app)
        case .closed: tracker.logClosed(appName: app)
        }
        NotificationCenter.default.post(name: .bobblySharedStateChanged, object: nil)
        return .result()
    }
}
