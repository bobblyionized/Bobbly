import XCTest
import SwiftData
@testable import Bobbly

/// End-to-end ViewModel flows on the Shortcuts engine with an in-memory
/// SwiftData store and an isolated App Group store (no FamilyControls needed).
final class ViewModelFlowTests: XCTestCase {

    @MainActor
    private func makeEnvironment() -> AppEnvironment {
        let shared = SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
        let env = AppEnvironment(container: BobblyModelContainer.make(inMemory: true), shared: shared, isPreview: true)
        env.chat.typingDelay = .zero
        env.engines.shortcuts.postsNotifications = false
        return env
    }

    /// Polls (yielding to the main actor) until `condition` holds or times out.
    @MainActor
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func testAddingCatalogAppBlocksIt() {
        let env = makeEnvironment()
        let blocked = env.makeBlockedAppsViewModel()
        blocked.onAppear()
        let instagram = AppCatalog.app(named: "Instagram")!
        blocked.add(instagram)
        XCTAssertTrue(blocked.isTracked(instagram))
        XCTAssertEqual(env.shared.blockedAppKeys, ["instagram"])
        XCTAssertFalse(env.engines.decision(forAppNamed: "Instagram").isAllowed)

        blocked.setLimit(blocked.trackedApps[0], minutes: 30)
        XCTAssertEqual(env.tracker.dailyLimits()["instagram"], 30)
        blocked.remove(blocked.trackedApps[0])
        XCTAssertTrue(env.shared.blockedAppKeys.isEmpty)
    }

    @MainActor
    func testChatGrantUnlocksAndLogs() async {
        let env = makeEnvironment()
        env.shared.blockedAppKeys = ["Instagram"]
        let target = ChatTarget(subject: .appName("Instagram"), displayName: "Instagram", origin: .gate)
        env.chat.start(target: target)
        await waitUntil { !env.chat.quickReplies.isEmpty }

        let work = env.chat.quickReplies.first { $0.kind == .reason(.work) }!
        env.chat.select(work)
        await waitUntil { env.chat.outcome != nil }

        guard case .granted(let name, let minutes, _, let costLife, _) = env.chat.outcome else {
            return XCTFail("expected a grant, got \(String(describing: env.chat.outcome))")
        }
        XCTAssertEqual(name, "Instagram")
        XCTAssertEqual(minutes, 15)
        XCTAssertFalse(costLife)
        XCTAssertTrue(env.engines.decision(forAppNamed: "Instagram").isAllowed)
        XCTAssertEqual(env.shared.unlocksToday(), 1)
        XCTAssertEqual(env.tracker.unlockEvents(in: UsageAggregator.lastDays(1)).count, 1)
    }

    @MainActor
    func testChatDeclineRaisesMood() async {
        let env = makeEnvironment()
        let moodBefore = env.companion.snapshot.mood
        env.chat.start(target: ChatTarget(subject: .appName("TikTok"), displayName: "TikTok", origin: .chatTab))
        await waitUntil { !env.chat.quickReplies.isEmpty }
        env.chat.draft = "I'm bored"
        env.chat.send()
        await waitUntil { env.chat.quickReplies.contains { $0.kind == .giveUp } }
        env.chat.select(env.chat.quickReplies.first { $0.kind == .giveUp }!)
        await waitUntil { env.chat.outcome != nil }
        XCTAssertEqual(env.chat.outcome, .declined)
        XCTAssertGreaterThan(env.companion.snapshot.mood, moodBefore)
        XCTAssertEqual(env.shared.unlocksToday(), 0)
    }

    @MainActor
    func testStudyWhitelistSessionLifecycle() async {
        let env = makeEnvironment()
        let study = env.study!
        study.newWhitelist()
        study.draft?.name = "Homework"
        study.toggleAllowed(appKey: "notes")
        XCTAssertTrue(study.saveDraft())
        XCTAssertEqual(study.whitelists.map(\.name), ["Homework"])

        study.selectedDuration = .minutes(25)
        study.startSession()
        XCTAssertNotNil(study.activeSession)
        XCTAssertTrue(env.engines.decision(forAppNamed: "Notes").isAllowed)
        XCTAssertFalse(env.engines.decision(forAppNamed: "YouTube").isAllowed)

        study.endSessionEarly(reason: "test")
        XCTAssertNil(study.activeSession)
        XCTAssertTrue(env.engines.decision(forAppNamed: "YouTube").isAllowed)
        let sessions = (try? env.context.fetch(FetchDescriptor<StudySession>())) ?? []
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions.first?.endedAt)
        XCTAssertEqual(sessions.first?.endedEarly, true)
    }

    @MainActor
    func testExpiredTimedStudyIsClosedOnSync() {
        let env = makeEnvironment()
        let study = env.study!
        study.newWhitelist()
        study.draft?.name = "Quick"
        XCTAssertTrue(study.saveDraft())
        study.selectedDuration = .minutes(25)
        study.startSession(now: Date().addingTimeInterval(-3600))
        study.syncWithEngine()
        XCTAssertNil(env.shared.activeStudy)
        XCTAssertNil(study.activeSession)
        let sessions = (try? env.context.fetch(FetchDescriptor<StudySession>())) ?? []
        XCTAssertEqual(sessions.first?.endedEarly, false)
        XCTAssertNotNil(sessions.first?.endedAt)
    }

    @MainActor
    func testStartOverFullyResetsTargetSoTheOldAppIsNeverUnlocked() async {
        let env = makeEnvironment()
        env.shared.blockedAppKeys = ["Instagram", "YouTube"]
        env.chat.start(target: ChatTarget(subject: .appName("Instagram"), displayName: "Instagram", origin: .gate))
        await waitUntil { !env.chat.quickReplies.isEmpty }
        env.chat.draft = "bored"
        env.chat.send()
        await waitUntil { env.chat.quickReplies.contains { $0.kind == .giveUp } }
        env.chat.select(env.chat.quickReplies.first { $0.kind == .giveUp }!)
        await waitUntil { env.chat.quickReplies.contains { $0.kind == .startOver } }
        XCTAssertEqual(env.chat.outcome, .declined)

        env.chat.select(env.chat.quickReplies.first { $0.kind == .startOver }!)
        XCTAssertNil(env.chat.target)
        XCTAssertNil(env.chat.outcome)
        XCTAssertEqual(env.chat.phase, .askingApp)
        await waitUntil { env.chat.acceptsFreeText }

        env.chat.draft = "YouTube"
        env.chat.send()
        await waitUntil { env.chat.quickReplies.contains { $0.kind == .reason(.work) } }
        env.chat.select(env.chat.quickReplies.first { $0.kind == .reason(.work) }!)
        await waitUntil { env.chat.outcome != nil }

        guard case .granted(let name, _, _, _, _) = env.chat.outcome else {
            return XCTFail("expected a grant, got \(String(describing: env.chat.outcome))")
        }
        XCTAssertEqual(name, "YouTube")
        XCTAssertTrue(env.engines.decision(forAppNamed: "YouTube").isAllowed)
        XCTAssertFalse(env.engines.decision(forAppNamed: "Instagram").isAllowed)
    }

    @MainActor
    func testTutorialPresentedBlockedAppsJumpsToScreenTimeStep() async {
        let env = makeEnvironment()
        let tutorial = env.makeTutorialViewModel()
        await tutorial.refreshStatuses()
        tutorial.isBlockedAppsPresented = true
        tutorial.currentIndex = tutorial.steps.count - 1

        let blocked = tutorial.makeBlockedAppsViewModel()
        XCTAssertTrue(blocked.isPresentedFromTutorial)
        blocked.openTutorial()
        XCTAssertFalse(tutorial.isBlockedAppsPresented)
        XCTAssertEqual(tutorial.currentStep?.id, .screenTime)
        XCTAssertNil(env.router.cover) // didn't try to re-present the tutorial

        XCTAssertFalse(env.makeBlockedAppsViewModel().isPresentedFromTutorial)
    }

    @MainActor
    func testOnAppearDoesNotWipeTargetedChat() async {
        let env = makeEnvironment()
        env.chat.start(target: ChatTarget(subject: .appName("Reddit"), displayName: "Reddit", origin: .gate))
        env.chat.onAppear() // first lines are still being presented asynchronously
        XCTAssertEqual(env.chat.target?.displayName, "Reddit")
        await waitUntil { !env.chat.quickReplies.isEmpty }
        XCTAssertEqual(env.chat.target?.displayName, "Reddit")
        XCTAssertEqual(env.chat.phase, .askingReason)
    }

    @MainActor
    func testGivingUpDuringCooldownCancelsItAndKeepsChatUsable() async {
        let env = makeEnvironment()
        env.chat.start(target: ChatTarget(subject: .appName("TikTok"), displayName: "TikTok", origin: .chatTab))
        await waitUntil { !env.chat.quickReplies.isEmpty }
        env.chat.draft = "bored"
        env.chat.send()
        await waitUntil { env.chat.quickReplies.contains { $0.kind == .unlockAnyway } }
        env.chat.select(env.chat.quickReplies.first { $0.kind == .unlockAnyway }!)
        await waitUntil { env.chat.quickReplies.contains { $0.kind == .waitCooldown } }
        env.chat.select(env.chat.quickReplies.first { $0.kind == .waitCooldown }!)
        await waitUntil { env.chat.cooldown != nil }
        XCTAssertNotNil(env.chat.cooldown)

        env.chat.select(env.chat.quickReplies.first { $0.kind == .giveUp }!)
        await waitUntil { env.chat.outcome != nil }
        XCTAssertEqual(env.chat.outcome, .declined)
        XCTAssertNil(env.chat.cooldown)
        XCTAssertTrue(env.chat.quickReplies.contains { $0.kind == .startOver })
    }

    @MainActor
    func testSiriStyleDetachClosesStudyWithoutBonus() async {
        let env = makeEnvironment()
        let study = env.study!
        study.newWhitelist()
        study.draft?.name = "Deep work"
        XCTAssertTrue(study.saveDraft())
        study.selectedDuration = .untilStopped
        study.startSession()
        let moodBefore = env.companion.snapshot.mood

        _ = await env.engines.detach()   // like the Siri intent: no stopSessionWithoutChat first
        study.syncWithEngine()

        let sessions = (try? env.context.fetch(FetchDescriptor<StudySession>())) ?? []
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.endedEarly, true)
        if let session = sessions.first, let end = session.endedAt {
            XCTAssertGreaterThanOrEqual(end, session.startedAt)
        } else {
            XCTFail("session not closed")
        }
        XCTAssertEqual(env.companion.snapshot.mood, moodBefore)
        XCTAssertTrue(env.engines.decision(forAppNamed: "Anything").isAllowed)
    }

    @MainActor
    func testGateLogsOneInterruption() {
        let env = makeEnvironment()
        env.shared.blockedAppKeys = ["Reddit"]
        let gate = env.makeGateViewModel(target: ChatTarget(subject: .appName("Reddit"), displayName: "Reddit", origin: .gate))
        gate.onAppear()
        gate.onAppear()
        XCTAssertFalse(gate.isAllowedNow)
        XCTAssertEqual(env.tracker.interruptionCount(in: UsageAggregator.lastDays(1)), 1)
        XCTAssertEqual(gate.headline, "Reddit is blocked")
    }

    @MainActor
    func testCheckAccessThenGateCountsOnce() {
        let env = makeEnvironment()
        env.shared.blockedAppKeys = ["Reddit"]
        // What CheckAccessIntent does on a denied check…
        env.tracker.logInterruption(appName: "reddit", source: .checkAccess)
        // …then its shortcut opens the Gate for the same attempt.
        let gate = env.makeGateViewModel(target: ChatTarget(subject: .appName("Reddit"), displayName: "Reddit", origin: .gate))
        gate.onAppear()
        XCTAssertEqual(env.tracker.interruptionCount(in: UsageAggregator.lastDays(1)), 1)
    }

    @MainActor
    func testShieldInterruptionsAreIngestedForEveryDay() {
        let env = makeEnvironment()
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        env.shared.incrementInterruptions(now: yesterday)
        env.shared.incrementInterruptions(now: yesterday)
        env.shared.incrementInterruptions(now: now)
        XCTAssertEqual(env.pendingShieldInterruptionsToday(now: now), 1)

        env.ingestShieldInterruptions(now: now)
        env.ingestShieldInterruptions(now: now) // idempotent
        XCTAssertEqual(env.pendingShieldInterruptionsToday(now: now), 0)
        XCTAssertEqual(env.tracker.interruptionCount(in: UsageAggregator.lastDays(2, now: now)), 3)
        XCTAssertEqual(env.tracker.interruptionCount(in: UsageAggregator.lastDays(1, now: now)), 1)
    }

    @MainActor
    func testLogAppEventsBuildSessions() {
        let env = makeEnvironment()
        let start = Date().addingTimeInterval(-600)
        env.tracker.logOpened(appName: "YouTube", at: start)
        env.tracker.logClosed(appName: "youtube", at: start.addingTimeInterval(300))
        let records = env.tracker.records(in: UsageAggregator.lastDays(1))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.end, start.addingTimeInterval(300))
    }

    @MainActor
    func testDeepLinkPresentsGate() async {
        let env = makeEnvironment()
        env.handle(url: URL(string: "bobbly://emergency")!)
        XCTAssertEqual(env.router.sheet, .emergency)

        // Sheet up → it is dismissed first, the gate cover follows after the hand-off delay.
        env.handle(url: URL(string: "bobbly://gate?app=Instagram")!)
        XCTAssertNil(env.router.sheet)
        XCTAssertNil(env.router.cover)
        await waitUntil { env.router.cover != nil }
        guard case .gate(let target) = env.router.cover else { return XCTFail("gate not presented") }
        XCTAssertEqual(target.displayName, "Instagram")
        XCTAssertEqual(target.reopenURL, URL(string: "instagram://"))

        env.handle(url: URL(string: "bobbly://chat?app=Instagram&source=shield")!)
        XCTAssertNil(env.router.cover)
        XCTAssertEqual(env.router.selectedTab, .chat)
        XCTAssertEqual(env.chat.target?.displayName, "Instagram")
    }
}
