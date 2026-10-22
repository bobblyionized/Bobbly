//  QuickSetupIntents.swift
//  Bobbly/Intents — the one-action Shortcuts setup.
//
//  Automation: "When <all distracting apps> Is Opened → Run Immediately →
//  Bobbly Gate". No If, no Open URL, no typing: when access is denied the
//  intent itself brings Bobbly to the Gate (iOS 26 `continueInForeground`).
//  Optional: "… Is Closed → Bobbly: App Closed" for usage time.

import AppIntents
import Foundation

extension Notification.Name {
    /// Posted (in-process) by `BobblyGateIntent` after it stored a pending gate request.
    static let bobblyGateRequested = Notification.Name("com.bobbly.gateRequested")
}

/// "Bobbly Gate" — checks access and, if blocked, opens Bobbly's Gate.
@available(iOS 26.0, *)
struct BobblyGateIntent: AppIntent {
    static var title: LocalizedStringResource = "Bobbly Gate"
    static var description: IntentDescription? = IntentDescription(
        "Add this to a “When an app is opened” automation. If Bobbly is blocking the app, it brings up Bobbly; otherwise the app just opens."
    )
    /// Background by default (fast "allowed" path); may move to the foreground
    /// to show the Gate.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    /// Optional. Leave empty when the automation covers several apps (group mode).
    @Parameter(title: "App")
    var app: String?

    init() {}

    init(app: String?) {
        self.app = app
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let now = Date()
        let shared = SharedStore.shared
        shared.recordGateIntentRun(at: now)

        let evaluation = GateIntentLogic.evaluate(
            appParameter: app,
            snapshot: shared.accessSnapshot(),
            closedAutomationDetected: shared.quickSetupRunStats.closedRuns > 0,
            now: now
        )
        let tracker = UsageTracker(context: BobblyModelContainer.shared.mainContext)
        tracker.logGateOpen(appName: evaluation.trackingName, tracksTime: evaluation.tracksSessionTime, at: now)

        let routing = GateIntentLogic.routing(showsGate: evaluation.showsGate,
                                              canContinueInForeground: systemContext.currentMode.canContinueInForeground)
        guard routing != .stayInBackground else {
            NotificationCenter.default.post(name: .bobblySharedStateChanged, object: nil)
            return .result()
        }

        // Blocked: one interruption per attempt (the Gate screen dedupes against it).
        tracker.logInterruption(appName: evaluation.trackingName, source: .checkAccess, at: now)
        let requestedApp: String? = evaluation.isGroup ? nil : evaluation.trackingName
        shared.pendingGateRequest = PendingGateRequest(appName: requestedApp, requestedAt: now)
        NotificationCenter.default.post(name: .bobblyGateRequested, object: nil)

        if routing == .continueInForeground {
            do {
                // alwaysConfirm: false → no extra confirmation when the person
                // just interacted (they literally just opened an app).
                try await continueInForeground(alwaysConfirm: false)
                return .result()
            } catch {
                shared.appendLog("Gate: couldn't continue in foreground (\(error)); sent a notification")
            }
        }
        BobblyNotifications.postGateRequest(appName: requestedApp)
        return .result()
    }
}

/// "Bobbly: App Closed" — optional; ends the usage session started by the Gate.
struct BobblyAppClosedIntent: AppIntent {
    static var title: LocalizedStringResource = "Bobbly: App Closed"
    static var description: IntentDescription? = IntentDescription(
        "Optional. Add this to a “When an app is closed” automation so Bobbly can track how long you spend in your blocked apps."
    )
    static var openAppWhenRun: Bool = false

    /// Optional. Leave empty when the automation covers several apps.
    @Parameter(title: "App")
    var app: String?

    init() {}

    init(app: String?) {
        self.app = app
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let now = Date()
        SharedStore.shared.recordAppClosedIntentRun(at: now)
        UsageTracker(context: BobblyModelContainer.shared.mainContext)
            .logClosed(appName: GateIntentLogic.closedTrackingName(appParameter: app), at: now)
        NotificationCenter.default.post(name: .bobblySharedStateChanged, object: nil)
        return .result()
    }
}
