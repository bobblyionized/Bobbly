//  PermissionsTutorialViewModel.swift
//  Bobbly/Features/Permissions — paged setup tutorial with a live ✅/❌ per
//  step. Shown on first launch; reopen from Settings › Permission tutorial.

import Foundation
import Observation
import SwiftData
import UIKit
import FamilyControls

enum TutorialStepID: String, CaseIterable, Identifiable {
    case trustDeveloper
    case screenTime
    case notifications
    case pickApps
    /// Only shown when FamilyControls failed (Shortcuts fallback).
    case shortcutsFallback
    case emergency

    var id: String { rawValue }
}

enum StepStatus: Equatable {
    /// ✅
    case complete
    /// ❌
    case incomplete
    /// Nice to have; no badge or a neutral "Optional" badge.
    case optional
    /// Status is being re-checked (show a spinner).
    case checking
}

enum TutorialAction: Equatable {
    /// Shows the system Screen Time prompt (AuthorizationCenter).
    case requestScreenTime
    /// Shows the system notification prompt.
    case requestNotifications
    /// Opens Bobbly's page in the Settings app.
    case openAppSettings
    /// Opens Bobbly's notification settings.
    case openNotificationSettings
    /// Presents BlockedAppsView (`isBlockedAppsPresented`).
    case pickBlockedApps
    /// Presents the whitelist editor (`isWhitelistEditorPresented`, uses `env.study`).
    case buildWhitelist
    /// Opens the Shortcuts app.
    case openShortcutsApp
    /// Presents EmergencyView (`isEmergencyPresented`).
    case openEmergencyScreen
}

struct TutorialButton: Equatable {
    let title: String
    let systemImage: String
    let action: TutorialAction
}

struct TutorialStep: Identifiable, Equatable {
    let id: TutorialStepID
    /// 1-based position among visible steps.
    var number: Int
    var title: String
    var body: String
    /// SF Symbol illustration.
    var systemImage: String
    /// Numbered how-to lines.
    var instructions: [String]
    var status: StepStatus
    /// e.g. "Screen Time access granted" / "Not allowed yet".
    var statusText: String
    var primary: TutorialButton?
    var secondary: TutorialButton?
}

@Observable
@MainActor
final class PermissionsTutorialViewModel {
    unowned let env: AppEnvironment

    /// Visible steps in order (the Shortcuts step appears only on the fallback engine).
    private(set) var steps: [TutorialStep] = []
    /// Page index into `steps` (bind to a paged TabView selection).
    var currentIndex: Int = 0
    /// An action is running (disable buttons, show progress).
    private(set) var isWorking = false

    // Sub-screens presented from within the tutorial cover.
    var isBlockedAppsPresented = false
    var isWhitelistEditorPresented = false
    var isEmergencyPresented = false

    // Shortcuts fallback step.
    var catalogQuery: String = ""
    /// Which catalog app's automation steps are expanded.
    var expandedCatalogAppID: String?
    private(set) var trackedAppKeys: Set<String> = []
    /// Times Bobbly's intents have run (proves the automations work).
    private(set) var automationRunCount: Int = 0

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Derived

    var currentStep: TutorialStep? { steps.indices.contains(currentIndex) ? steps[currentIndex] : nil }
    var isFirstStep: Bool { currentIndex == 0 }
    var isLastStep: Bool { currentIndex >= steps.count - 1 }
    /// 0...1 page progress.
    var progress: Double { steps.isEmpty ? 0 : Double(currentIndex + 1) / Double(steps.count) }
    var completedCount: Int { steps.filter { $0.status == .complete }.count }

    var catalog: [CatalogApp] { AppCatalog.search(catalogQuery) }

    func isTracked(_ app: CatalogApp) -> Bool { trackedAppKeys.contains(app.id) }

    func automationSteps(for app: CatalogApp) -> [String] { AppCatalog.automationSteps(for: app.name) }

    // MARK: Actions

    func onAppear() async {
        await refreshStatuses()
    }

    /// Re-checks every step (also call when the scene becomes active again,
    /// e.g. after returning from the Settings app).
    func refreshStatuses() async {
        await env.notifications.refresh()
        let tracked = (try? env.context.fetch(FetchDescriptor<TrackedApp>())) ?? []
        trackedAppKeys = Set(tracked.map(\.appKey))
        automationRunCount = ((try? env.context.fetchCount(FetchDescriptor<UsageSession>())) ?? 0)
        rebuildSteps()
    }

    func next() {
        if currentIndex < steps.count - 1 { currentIndex += 1 }
    }

    func back() {
        if currentIndex > 0 { currentIndex -= 1 }
    }

    func goTo(_ id: TutorialStepID) {
        if let index = steps.firstIndex(where: { $0.id == id }) { currentIndex = index }
    }

    func perform(_ action: TutorialAction) async {
        isWorking = true
        defer { isWorking = false }
        switch action {
        case .requestScreenTime:
            await env.engines.requestFamilyControls()
            env.refreshAll()
        case .requestNotifications:
            await env.notifications.requestAuthorization()
        case .openAppSettings:
            await open(UIApplication.openSettingsURLString)
        case .openNotificationSettings:
            await open(UIApplication.openNotificationSettingsURLString)
        case .pickBlockedApps:
            isBlockedAppsPresented = true
        case .buildWhitelist:
            env.study.newWhitelist()
            isWhitelistEditorPresented = true
        case .openShortcutsApp:
            await open("shortcuts://")
        case .openEmergencyScreen:
            isEmergencyPresented = true
        }
        await refreshStatuses()
    }

    /// Shortcuts step: track/untrack a popular app (tracked apps are blocked).
    func toggleTracked(_ app: CatalogApp) {
        let key = app.id
        let descriptor = FetchDescriptor<TrackedApp>(predicate: #Predicate { $0.appKey == key })
        if let existing = try? env.context.fetch(descriptor).first {
            env.context.delete(existing)
        } else {
            env.context.insert(TrackedApp(name: app.name, urlScheme: app.urlScheme))
        }
        try? env.context.save()
        let names = ((try? env.context.fetch(FetchDescriptor<TrackedApp>())) ?? []).filter(\.isBlocked).map(\.name)
        try? env.engines.updateBlockList(BlockList(selection: env.shared.blockedSelection, appNames: names))
        Task { await refreshStatuses() }
    }

    /// Marks the tutorial done and closes it.
    func finish() {
        env.preferences.hasCompletedTutorial = true
        env.router.dismissCover()
        env.refreshAll()
    }

    // MARK: Step building

    private func rebuildSteps() {
        let fcStatus = env.engines.familyControls.authorizationStatus
        let fallback: Bool
        if case .shortcutsFallback = env.engines.state { fallback = true } else { fallback = false }
        let notifications = env.notifications
        let status = env.engines.status

        var built: [TutorialStep] = []

        built.append(TutorialStep(
            id: .trustDeveloper, number: 0, title: "Trust Bobbly",
            body: "Sideloaded apps need to be trusted once. If Bobbly opened, you're already done.",
            systemImage: "checkmark.shield",
            instructions: [
                "If iOS said \"Untrusted Developer\": open Settings › General › VPN & Device Management.",
                "Tap your Apple ID / developer profile, then Trust.",
                "If asked, turn on Settings › Privacy & Security › Developer Mode and restart.",
            ],
            status: .complete, statusText: "Bobbly is running, so it's trusted.",
            primary: nil, secondary: nil))

        let screenTimeDone = fcStatus == .approved
        built.append(TutorialStep(
            id: .screenTime, number: 0, title: "Screen Time access",
            body: "This lets Bobbly put a real shield over apps you choose. Your data never leaves your phone.",
            systemImage: "hourglass",
            instructions: [
                "Tap Allow Screen Time access.",
                "Confirm with Face ID / your passcode.",
                "If it fails, Bobbly switches to Shortcuts mode automatically.",
            ],
            status: screenTimeDone ? .complete : .incomplete,
            statusText: screenTimeDone ? "Screen Time access granted"
                : (fcStatus == .denied ? "Denied — Bobbly is using Shortcuts mode" : "Not allowed yet"),
            primary: screenTimeDone ? nil : TutorialButton(title: "Allow Screen Time access", systemImage: "hand.raised", action: .requestScreenTime),
            secondary: nil))

        built.append(TutorialStep(
            id: .notifications, number: 0, title: "Notifications",
            body: "The shield's \"Talk to Bobbly\" button sends you a notification to open the chat, and Bobbly warns you before an unlock ends.",
            systemImage: "bell.badge",
            instructions: ["Tap Allow notifications.", "Keep banners on so you can tap through from the shield."],
            status: notifications.isAuthorized ? .complete : .incomplete,
            statusText: notifications.isAuthorized ? "Notifications on" : (notifications.isDenied ? "Turned off in Settings" : "Not allowed yet"),
            primary: notifications.isAuthorized ? nil
                : (notifications.isDenied
                    ? TutorialButton(title: "Open notification settings", systemImage: "gear", action: .openNotificationSettings)
                    : TutorialButton(title: "Allow notifications", systemImage: "bell", action: .requestNotifications)),
            secondary: nil))

        built.append(TutorialStep(
            id: .pickApps, number: 0, title: "Pick apps to block",
            body: "Choose the apps that steal your time. Optionally build a study whitelist: the only apps allowed while you study.",
            systemImage: "apps.iphone",
            instructions: ["Tap Choose apps and select apps, categories or websites.", "Study whitelists live in the Study tab."],
            status: status.hasAnythingBlocked ? .complete : .incomplete,
            statusText: status.hasAnythingBlocked ? "Blocking \(status.blockedAppCount + status.blockedCategoryCount + status.blockedWebDomainCount) item(s)" : "Nothing blocked yet",
            primary: TutorialButton(title: "Choose apps", systemImage: "plus.app", action: .pickBlockedApps),
            secondary: TutorialButton(title: "Build a study whitelist", systemImage: "book", action: .buildWhitelist)))

        if fallback {
            let working = automationRunCount > 0
            built.append(TutorialStep(
                id: .shortcutsFallback, number: 0, title: "Shortcuts automations",
                body: "Screen Time access isn't available, so Bobbly uses Shortcuts automations instead. iOS doesn't let apps create them, so follow the steps for each app below.",
                systemImage: "square.stack.3d.up",
                instructions: [
                    "Pick your apps from the list below.",
                    "For each app, create the two automations shown.",
                    "Open the app once to test: Bobbly should appear.",
                ],
                status: working ? .complete : .incomplete,
                statusText: working ? "Automations detected (\(automationRunCount) runs)" : "No automation runs seen yet",
                primary: TutorialButton(title: "Open Shortcuts", systemImage: "arrow.up.forward.app", action: .openShortcutsApp),
                secondary: nil))
        }

        built.append(TutorialStep(
            id: .emergency, number: 0, title: "Emergencies",
            body: "Emergency unblock is always free. Emergency detach turns Bobbly off completely. Both work even if the app breaks.",
            systemImage: "light.beacon.max",
            instructions: [
                "Home › Emergency, or Settings › Emergency.",
                "Hold the button for 10 seconds to confirm.",
                "Or say \"Hey Siri, Bobbly emergency\" / \"Hey Siri, detach Bobbly\".",
                "Or open the link bobbly://emergency.",
            ],
            status: .complete, statusText: "Always available",
            primary: TutorialButton(title: "See the Emergency screen", systemImage: "exclamationmark.octagon", action: .openEmergencyScreen),
            secondary: nil))

        for index in built.indices { built[index].number = index + 1 }
        steps = built
        currentIndex = min(currentIndex, max(0, steps.count - 1))
    }

    private func open(_ string: String) async {
        guard let url = URL(string: string) else { return }
        _ = await UIApplication.shared.open(url)
    }
}
