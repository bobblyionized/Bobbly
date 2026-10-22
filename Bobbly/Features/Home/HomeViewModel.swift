//  HomeViewModel.swift
//  Bobbly/Features/Home — status, companion and quick actions.

import Foundation
import Observation
import DeviceActivity
import SwiftUI

/// The headline protection state shown on Home.
enum ProtectionState: Equatable {
    /// Nothing blocked yet, or Screen Time access not set up.
    case setupNeeded
    /// Blocking is active.
    case protecting(blockedCount: Int)
    /// At least one chat unlock is running (soonest-expiring shown).
    case unlocked(appName: String, until: Date)
    /// A study session is running (`until == nil` = until stopped).
    case studying(name: String, until: Date?)
    /// Emergency unblock is running.
    case emergency(until: Date)
    /// Emergency detach: Bobbly is off.
    case detached
}

/// Buttons in Home's quick-action grid.
enum HomeQuickAction: String, CaseIterable, Identifiable {
    case talkToBobbly
    case startStudy
    case editBlockedApps
    case search
    case emergency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talkToBobbly: return "Talk to Bobbly"
        case .startStudy: return "Study session"
        case .editBlockedApps: return "Blocked apps"
        case .search: return "Search usage"
        case .emergency: return "Emergency"
        }
    }

    var systemImage: String {
        switch self {
        case .talkToBobbly: return "bubble.left.fill"
        case .startStudy: return "book.fill"
        case .editBlockedApps: return "lock.app.dashed"
        case .search: return "magnifyingglass"
        case .emergency: return "exclamationmark.octagon.fill"
        }
    }
}

@Observable
@MainActor
final class HomeViewModel {
    unowned let env: AppEnvironment

    /// Headline state (drives the big status card).
    private(set) var protection: ProtectionState = .setupNeeded
    /// Running chat unlocks, soonest first. Each has `expiresAt` for a countdown.
    private(set) var activeUnlocks: [ActiveUnlock] = []
    /// Chat unlocks granted today.
    private(set) var unlocksToday: Int = 0
    /// Unlocks left today before one costs Bobbly a life (never negative).
    private(set) var freeUnlocksLeft: Int = 0
    /// Blocked attempts today (gate + shield + Shortcuts checks).
    private(set) var interruptionsToday: Int = 0
    /// Shortcuts engine: minutes in tracked apps today. `nil` under FamilyControls
    /// (embed the `todayReport…` DeviceActivityReport instead).
    private(set) var screenMinutesToday: Double?

    /// Quick actions in display order.
    let quickActions: [HomeQuickAction] = HomeQuickAction.allCases

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Derived (observation flows through env's observable services)

    /// Bobbly's mood/lives for the header character.
    var companion: CompanionSnapshot { env.companion.snapshot }

    var engineKind: EngineKind { env.engines.status.kind }

    /// e.g. "Screen Time (FamilyControls)" / "Shortcuts fallback".
    var engineLabel: String { env.engines.state.label }

    /// "Good morning" / "Good afternoon" / "Good evening".
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// Separate block-list counts (the `.protecting(blockedCount:)` total merges them).
    var blockedAppCount: Int { env.engines.status.blockedAppCount }
    var blockedCategoryCount: Int { env.engines.status.blockedCategoryCount }
    var blockedWebsiteCount: Int { env.engines.status.blockedWebDomainCount }

    /// `true` after Screen Time access was revoked (detach, or turned off in
    /// Settings): the saved app picks are void and must be chosen again.
    /// Show a "Pick your apps again" call to action (→ `perform(.editBlockedApps)`).
    var needsAppRepick: Bool {
        env.engines.state == .familyControls && env.engines.familyControls.isAuthorized
            && !env.engines.status.hasAnythingBlocked && env.shared.tokensRevokedAt != nil
    }

    /// FamilyControls only: embed `DeviceActivityReport(todayReportContext, filter: todayReportFilter)`.
    var showsTodayReport: Bool { engineKind == .familyControls }
    var todayReportContext: DeviceActivityReport.Context { .bobblyTodaySummary }
    var todayReportFilter: DeviceActivityFilter { ReportFilters.today() }

    // MARK: Actions

    func onAppear() {
        refresh()
    }

    /// Re-reads engine status and today's counters.
    func refresh() {
        let now = Date()
        let status = env.engines.status
        activeUnlocks = status.activeUnlocks
        unlocksToday = env.shared.unlocksToday(now: now)
        freeUnlocksLeft = max(0, env.preferences.dailyFreeUnlocks - unlocksToday)

        let today = UsageAggregator.lastDays(1, now: now)
        interruptionsToday = env.tracker.interruptionCount(in: today) + env.pendingShieldInterruptionsToday(now: now)

        if status.kind == .shortcuts {
            let records = env.tracker.records(in: today)
            screenMinutesToday = UsageAggregator.summaries(records, range: today, now: now).reduce(0) { $0 + $1.totalMinutes }
        } else {
            screenMinutesToday = nil
        }

        protection = Self.protectionState(status: status, engineState: env.engines.state, now: now)
    }

    func perform(_ action: HomeQuickAction) {
        switch action {
        case .talkToBobbly: env.openChat(nil)
        case .startStudy: env.router.showTab(.study)
        case .editBlockedApps: env.router.present(.blockedApps)
        case .search: env.router.present(.search)
        case .emergency: env.router.present(.emergency)
        }
    }

    /// "Lock it again" on a running unlock.
    func relock(_ unlock: ActiveUnlock) {
        env.engines.revokeUnlock(id: unlock.id)
        refresh()
    }

    /// Opens the companion detail sheet.
    func openCompanion() {
        env.router.present(.companion)
    }

    /// Opens the permissions tutorial (used by the `.setupNeeded` card).
    func openSetup() {
        env.router.presentTutorial()
    }

    // MARK: Helpers

    static func protectionState(status: EngineStatus, engineState: EngineSelectionState, now: Date) -> ProtectionState {
        if status.isDetached || engineState == .detached { return .detached }
        if let until = status.emergencyUntil, until > now { return .emergency(until: until) }
        if let study = status.study { return .studying(name: study.whitelistName, until: study.endsAt) }
        if let first = status.activeUnlocks.first { return .unlocked(appName: first.displayName, until: first.expiresAt) }
        if engineState == .undetermined || !status.hasAnythingBlocked { return .setupNeeded }
        return .protecting(blockedCount: status.blockedAppCount + status.blockedCategoryCount + status.blockedWebDomainCount)
    }
}
