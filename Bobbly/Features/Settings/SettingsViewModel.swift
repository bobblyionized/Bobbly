//  SettingsViewModel.swift
//  Bobbly/Features/Settings — preferences, engine diagnostics (which engine
//  is running and why), tutorial + emergency entry points.

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SettingsViewModel {
    unowned let env: AppEnvironment

    /// Shown after "Copy diagnostics".
    private(set) var didCopyDiagnostics = false

    let freeUnlockOptions = [0, 1, 2, 3, 4, 5, 7, 10]
    let emergencyMinuteOptions = [15, 30, 60, 120, 240]

    /// Quick setup › "Blocking on/off" (group automation). Off = the automation
    /// only tracks usage; the Gate never appears for the group.
    var quickSetupBlockingEnabled: Bool {
        didSet { env.shared.groupBlockingEnabled = quickSetupBlockingEnabled }
    }

    /// "Test it" status for the quick-setup automations (refreshed in `refresh()`).
    private(set) var quickSetupStatus: QuickSetupStatus

    init(env: AppEnvironment) {
        self.env = env
        self.quickSetupBlockingEnabled = env.shared.groupBlockingEnabled
        self.quickSetupStatus = QuickSetupStatus(env.shared.quickSetupRunStats)
    }

    // MARK: Shortcuts setup

    /// `.quick` (one automation, default on iOS 26+) or `.perApp` (advanced).
    var setupMode: SetupMode {
        get { env.preferences.setupMode }
        set { env.preferences.setupMode = newValue }
    }

    /// Quick setup needs iOS 26; hide the choice (and show per-app) otherwise.
    var isQuickSetupAvailable: Bool { QuickSetup.isAvailable }
    var setupModeOptions: [SetupMode] { isQuickSetupAvailable ? SetupMode.allCases : [.perApp] }

    /// Settings rows about Shortcuts setup only matter on the Shortcuts engine.
    var showsShortcutsSetup: Bool { env.engines.kind == .shortcuts }

    // MARK: Preferences (two-way; use `@Bindable var model` + `$model.dailyFreeUnlocks`)

    var dailyFreeUnlocks: Int {
        get { env.preferences.dailyFreeUnlocks }
        set { env.preferences.dailyFreeUnlocks = newValue }
    }

    var defaultEmergencyMinutes: Int {
        get { env.preferences.defaultEmergencyMinutes }
        set { env.preferences.defaultEmergencyMinutes = newValue }
    }

    var hapticsEnabled: Bool {
        get { env.preferences.hapticsEnabled }
        set { env.preferences.hapticsEnabled = newValue }
    }

    // MARK: Diagnostics

    var diagnostics: EngineDiagnostics { env.engines.diagnostics }
    var engineState: EngineSelectionState { env.engines.state }
    var isRequestingAuthorization: Bool { env.engines.isRequestingAuthorization }
    var notificationsAuthorized: Bool { env.notifications.isAuthorized }

    /// Short explanation under the engine row, e.g. why the fallback is running.
    var engineExplanation: String {
        switch env.engines.state {
        case .undetermined:
            return "Screen Time access hasn't been requested yet. Open the permission tutorial to set up blocking."
        case .familyControls:
            return "Real blocking is on: Bobbly shields apps with Screen Time."
        case .shortcutsFallback(let reason):
            return "\(reason) Bobbly is using Shortcuts automations instead (a softer block)."
        case .detached:
            return "Bobbly is detached and isn't blocking anything. Use Emergency › Turn Bobbly back on."
        }
    }

    /// Show "Retry Screen Time access" when not on FamilyControls — or when the
    /// engine is kept on FamilyControls without current authorization (unclear
    /// re-request, retrying in the background).
    var canRetryScreenTime: Bool {
        AuthorizationRules.canRetryScreenTime(state: env.engines.state,
                                              isAuthorized: env.engines.familyControls.isAuthorized)
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: Actions

    func onAppear() {
        refresh()
    }

    func refresh() {
        env.engines.refresh()
        didCopyDiagnostics = false
        quickSetupStatus = QuickSetupStatus(env.shared.quickSetupRunStats)
        if quickSetupBlockingEnabled != env.shared.groupBlockingEnabled {
            quickSetupBlockingEnabled = env.shared.groupBlockingEnabled
        }
    }

    func openTutorial() { env.router.presentTutorial() }
    func openEmergency() { env.router.present(.emergency) }
    func openBlockedApps() { env.router.present(.blockedApps) }
    func openCompanion() { env.router.present(.companion) }

    /// Shows the Screen Time prompt again; falls back on failure.
    func retryScreenTimeAccess() async {
        await env.engines.requestFamilyControls()
        env.refreshAll()
    }

    func switchToShortcutsFallback() {
        env.engines.useShortcutsFallback()
        env.refreshAll()
    }

    /// Plain-text diagnostics for bug reports.
    func diagnosticsReport() -> String {
        let d = diagnostics
        var lines = [
            "Bobbly \(appVersion)",
            "Engine: \(d.activeEngine.displayName)",
            "State: \(d.selectionState.label)",
            "Screen Time authorization: \(d.authorizationStatus)",
            "App Group available: \(d.appGroupAvailable ? "yes" : "NO — extensions can't read Bobbly's state")",
            "Data store: \(d.usingFallbackDataStore ? "in-memory fallback" : "on disk")",
            "Notifications: \(notificationsAuthorized ? "on" : "off")",
            "Monitored activities: \(d.monitoredActivities.count)",
            "Shortcuts setup: \(setupMode.title); Gate runs: \(quickSetupStatus.gateRuns); App Closed runs: \(quickSetupStatus.closedRuns); quick-setup blocking: \(quickSetupBlockingEnabled ? "on" : "off")",
        ]
        if let error = d.lastAuthorizationError { lines.append("Last auth error: \(error)") }
        if let error = d.lastMonitoringError { lines.append("Last monitoring error: \(error)") }
        lines.append("— recent log —")
        lines.append(contentsOf: d.recentLog)
        return lines.joined(separator: "\n")
    }

    func copyDiagnostics() {
        UIPasteboard.general.string = diagnosticsReport()
        didCopyDiagnostics = true
    }
}
