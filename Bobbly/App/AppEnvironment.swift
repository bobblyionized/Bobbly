//  AppEnvironment.swift
//  Bobbly/App — dependency container + orchestration. Injected into the view
//  tree with `.environment(env)`; views read it via `@Environment(AppEnvironment.self)`.
//
//  Tab ViewModels are long-lived properties (`env.home`, `env.chat`, …).
//  Modal ViewModels are created with `env.make…ViewModel()` and owned by the
//  presenting view in `@State` (their inits are side-effect free; call `onAppear()`).

import Foundation
import Observation
import SwiftData

extension Notification.Name {
    /// Posted (in-process) by App Intents after they change SharedStore/SwiftData.
    static let bobblySharedStateChanged = Notification.Name("com.bobbly.sharedStateChanged")
}

@Observable
@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let shared: SharedStore
    let tracker: UsageTracker
    let isPreview: Bool

    let preferences: Preferences
    let engines: EngineSelector
    let companion: CompanionService
    let notifications: NotificationService
    let router: AppRouter

    // Long-lived tab ViewModels (set at the end of init; never nil afterwards).
    @ObservationIgnored private(set) var home: HomeViewModel!
    @ObservationIgnored private(set) var chat: ChatViewModel!
    @ObservationIgnored private(set) var study: StudyViewModel!
    @ObservationIgnored private(set) var stats: StatsViewModel!
    @ObservationIgnored private(set) var settings: SettingsViewModel!

    @ObservationIgnored private var didLaunch = false
    @ObservationIgnored private var sharedStateObserver: NSObjectProtocol?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    var context: ModelContext { container.mainContext }

    init(container: ModelContainer = BobblyModelContainer.shared,
         shared: SharedStore = .shared,
         isPreview: Bool = false) {
        self.container = container
        self.shared = shared
        self.isPreview = isPreview
        self.tracker = UsageTracker(context: container.mainContext)
        self.preferences = Preferences(shared: shared)
        self.engines = EngineSelector(shared: shared)
        self.companion = CompanionService(context: container.mainContext, shared: shared)
        self.notifications = NotificationService()
        self.router = AppRouter()

        self.home = HomeViewModel(env: self)
        self.chat = ChatViewModel(env: self)
        self.study = StudyViewModel(env: self)
        self.stats = StatsViewModel(env: self)
        self.settings = SettingsViewModel(env: self)
    }

    /// In-memory environment with sample data for SwiftUI previews.
    static func preview() -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "bobbly.preview") ?? .standard
        return AppEnvironment(container: BobblyModelContainer.preview(), shared: SharedStore(defaults: defaults), isPreview: true)
    }

    // MARK: - Modal ViewModel factories

    func makeGateViewModel(target: ChatTarget) -> GateViewModel { GateViewModel(env: self, target: target) }
    func makeEmergencyViewModel() -> EmergencyViewModel { EmergencyViewModel(env: self) }
    func makeSearchViewModel() -> SearchViewModel { SearchViewModel(env: self) }
    func makeTutorialViewModel() -> PermissionsTutorialViewModel { PermissionsTutorialViewModel(env: self) }
    func makeBlockedAppsViewModel() -> BlockedAppsViewModel { BlockedAppsViewModel(env: self) }
    func makeCompanionViewModel() -> CompanionViewModel { CompanionViewModel(env: self) }

    // MARK: - Lifecycle

    /// Called once from the root view's `.task`.
    func launch() async {
        guard !didLaunch, !isPreview else { return }
        didLaunch = true
        observeSharedStateChanges()
        await notifications.refresh()
        await engines.bootstrap(requestIfNeeded: preferences.hasCompletedTutorial)
        engines.reconcileNow()
        companion.refresh()
        ingestShieldInterruptions()
        study.syncWithEngine()
        creditPassiveFocus()
        refreshAll()
        if !preferences.hasCompletedTutorial {
            router.presentTutorial()
        }
    }

    /// Called whenever the scene becomes active.
    func sceneDidBecomeActive() async {
        guard didLaunch else { return }
        await notifications.refresh()
        await engines.bootstrap(requestIfNeeded: false)
        engines.reconcileNow()
        companion.refresh()
        ingestShieldInterruptions()
        study.syncWithEngine()
        creditPassiveFocus()
        refreshAll()
    }

    /// Presents a sheet, first dismissing a full-screen cover if one is up
    /// (SwiftUI can't present a root sheet while a cover is showing).
    /// `router.present(_:)` now does this sequencing itself; kept for callers.
    func presentSheet(_ route: SheetRoute) {
        router.present(route)
    }

    /// Credits protected time since the last credit to Bobbly's mood.
    private func creditPassiveFocus(now: Date = Date()) {
        let status = engines.status
        let protecting = engines.state != .undetermined && !status.isDetached && status.hasAnythingBlocked
        let today = UsageAggregator.lastDays(1, now: now)
        let unlockedWindows = tracker.unlockEvents(in: today)
            .filter(\.granted)
            .map { DateInterval(start: $0.date, duration: TimeInterval(max(0, $0.minutes) * 60)) }
        companion.creditPassiveFocus(isProtecting: protecting, excluded: unlockedWindows, now: now)
    }

    /// Re-pulls state into the tab ViewModels.
    func refreshAll() {
        engines.refresh()
        home.refresh()
        study.refresh()
        stats.refresh()
        settings.refresh()
        if !isPreview { scheduleExpiryRefresh() }
    }

    /// While Bobbly is open, refreshes everything right after the next unlock /
    /// emergency / study session ends, so countdowns don't linger at 0:00.
    private func scheduleExpiryRefresh(now: Date = Date()) {
        expiryTask?.cancel()
        let status = engines.status
        var candidates: [Date] = status.activeUnlocks.map(\.expiresAt)
        if let until = status.emergencyUntil { candidates.append(until) }
        if let end = status.study?.endsAt { candidates.append(end) }
        guard let next = candidates.filter({ $0 > now }).min() else { return }
        let delay = next.timeIntervalSince(now) + 1
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.engines.reconcileNow()
            self.study.syncWithEngine()
            self.refreshAll()
        }
    }

    private func observeSharedStateChanges() {
        sharedStateObserver = NotificationCenter.default.addObserver(
            forName: .bobblySharedStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // An intent may have detached Bobbly or changed timed state.
                await self.engines.bootstrap(requestIfNeeded: false)
                self.study.syncWithEngine()
                self.refreshAll()
            }
        }
    }

    // MARK: - Deep links

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        handle(link)
    }

    func handle(_ link: DeepLink) {
        switch link {
        case .gate(let appName, _):
            let target = makeTarget(appName: appName, origin: .gate)
                ?? ChatTarget(subject: .appName("App"), displayName: "this app", origin: .gate)
            router.presentGate(target)

        case .chat(let appName, let source):
            if source == .shield, let pending = shared.pendingShieldRequest {
                shared.pendingShieldRequest = nil
                if let token = pending.applicationToken {
                    openChat(ChatTarget(subject: .application(token), displayName: pending.appName ?? appName ?? "this app", origin: .shield))
                    return
                }
            }
            openChat(makeTarget(appName: appName, origin: source == .shield ? .shield : .chatTab))

        case .emergency:
            presentSheet(.emergency)

        case .tutorial:
            router.presentTutorial()
        }
    }

    /// Switches to the Chat tab and starts a conversation (`nil` = ask which app).
    func openChat(_ target: ChatTarget?) {
        router.showTab(.chat)
        chat.start(target: target)
    }

    /// Builds a name-based target, enriching it with the tracked app's URL scheme.
    func makeTarget(appName: String?, origin: ChatOrigin) -> ChatTarget? {
        guard let appName, !appName.isEmpty else { return nil }
        let key = AppKey.normalize(appName)
        let descriptor = FetchDescriptor<TrackedApp>(predicate: #Predicate { $0.appKey == key })
        let tracked = try? context.fetch(descriptor).first
        let catalog = AppCatalog.app(named: appName)
        let reopen = tracked?.openURL ?? catalog.flatMap { URL(string: "\($0.urlScheme)://") }
        return ChatTarget(subject: .appName(tracked?.name ?? appName),
                          displayName: tracked?.name ?? catalog?.name ?? appName,
                          origin: origin, reopenURL: reopen)
    }

    // MARK: - Shield counters → history

    /// Per-day counts already copied into SwiftData (`SharedStore.dayKey` → count).
    private var importedShieldInterruptions: [String: Int] {
        get { shared.importedInterruptionsByDay }
        set { shared.importedInterruptionsByDay = newValue }
    }

    /// Moves new shield interruptions (counted per day by the shield-action
    /// extension in SharedStore) into SwiftData so Stats has history — for
    /// every day, including days Bobbly wasn't opened.
    func ingestShieldInterruptions(now: Date = Date()) {
        let sharedCounts = shared.interruptionsByDay
        var imported = importedShieldInterruptions
        for item in InterruptionIngest.pending(shared: sharedCounts, imported: imported) {
            tracker.logInterruption(appName: "Shielded apps", source: .shield, count: item.delta,
                                    at: InterruptionIngest.date(forDayKey: item.dayKey, now: now))
            imported[item.dayKey, default: 0] += item.delta
        }
        importedShieldInterruptions = imported.filter { sharedCounts[$0.key] != nil }
    }

    /// Shield interruptions today that aren't in SwiftData yet.
    func pendingShieldInterruptionsToday(now: Date = Date()) -> Int {
        let key = SharedStore.dayKey(now)
        return max(0, shared.interruptionsToday(now: now) - (importedShieldInterruptions[key] ?? 0))
    }
}
