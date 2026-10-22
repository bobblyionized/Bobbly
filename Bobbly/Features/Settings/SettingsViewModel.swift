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

    init(env: AppEnvironment) {
        self.env = env
    }

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

    /// Show "Retry Screen Time access" when not on FamilyControls.
    var canRetryScreenTime: Bool { env.engines.state != .familyControls }

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
