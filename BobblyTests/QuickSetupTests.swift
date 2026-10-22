import XCTest
import SwiftData
@testable import Bobbly

/// Quick setup (Shortcuts GROUP mode): one "Bobbly Gate" automation for all apps.
final class QuickSetupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(detached: Bool = false, emergencyUntil: Date? = nil, blocked: Set<String> = [],
                          grants: [UnlockGrant] = [], study: ActiveStudy? = nil, groupBlocking: Bool = true) -> AccessSnapshot {
        AccessSnapshot(isDetached: detached, emergencyUntil: emergencyUntil, blockedAppKeys: blocked,
                       grants: grants, study: study, groupBlockingEnabled: groupBlocking)
    }

    private func grant(_ key: String, minutes: Double = 10) -> UnlockGrant {
        UnlockGrant(appKey: key, tokenData: nil, displayName: key, grantedAt: now, expiresAt: now.addingTimeInterval(minutes * 60))
    }

    private var study: ActiveStudy {
        ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "Homework", selectionData: nil,
                    allowedAppKeys: ["notes"], startedAt: now, endsAt: nil)
    }

    // MARK: Group access decisions

    func testGroupIsBlockedByDefault() {
        XCTAssertEqual(AccessPolicy.decide(appName: AppKey.group, snapshot: snapshot(), now: now), .blocked(.blockedApp))
    }

    func testGroupPrecedence() {
        XCTAssertEqual(AccessPolicy.decide(appName: AppKey.group, snapshot: snapshot(detached: true, study: study), now: now), .allowed(.detached))
        XCTAssertEqual(AccessPolicy.decide(appName: AppKey.group, snapshot: snapshot(emergencyUntil: now.addingTimeInterval(60), study: study), now: now),
                       .allowed(.emergency(until: now.addingTimeInterval(60))))
        let g = grant(AppKey.group)
        XCTAssertEqual(AccessPolicy.decide(appName: AppKey.group, snapshot: snapshot(grants: [g], study: study), now: now),
                       .allowed(.unlocked(until: g.expiresAt)))
        XCTAssertEqual(AccessPolicy.decide(appName: AppKey.group, snapshot: snapshot(study: study), now: now),
                       .blocked(.studySession(whitelistName: "Homework")))
        XCTAssertEqual(AccessPolicy.decide(appName: AppKey.group, snapshot: snapshot(groupBlocking: false), now: now), .allowed(.notBlocked))
        // Study still blocks the group even with quick-setup blocking off.
        XCTAssertEqual(AccessPolicy.decide(appName: AppKey.group, snapshot: snapshot(study: study, groupBlocking: false), now: now),
                       .blocked(.studySession(whitelistName: "Homework")))
    }

    func testGrantScoping() {
        // A group unlock doesn't unlock per-app (advanced setup) apps, and vice versa.
        let s1 = snapshot(blocked: ["instagram"], grants: [grant(AppKey.group)])
        XCTAssertTrue(AccessPolicy.decide(appName: AppKey.group, snapshot: s1, now: now).isAllowed)
        XCTAssertFalse(AccessPolicy.decide(appName: "Instagram", snapshot: s1, now: now).isAllowed)
        let s2 = snapshot(blocked: ["instagram"], grants: [grant("instagram")])
        XCTAssertFalse(AccessPolicy.decide(appName: AppKey.group, snapshot: s2, now: now).isAllowed)
        XCTAssertTrue(AccessPolicy.decide(appName: "Instagram", snapshot: s2, now: now).isAllowed)
        // Expired group grant → blocked again.
        let expired = snapshot(grants: [grant(AppKey.group, minutes: -1)])
        XCTAssertFalse(AccessPolicy.decide(appName: AppKey.group, snapshot: expired, now: now).isAllowed)
    }

    // MARK: Gate intent logic

    func testAppParameterNormalization() {
        XCTAssertNil(GateIntentLogic.appName(from: nil))
        XCTAssertNil(GateIntentLogic.appName(from: "   "))
        XCTAssertNil(GateIntentLogic.appName(from: "Blocked apps"))
        XCTAssertNil(GateIntentLogic.appName(from: AppKey.group))
        XCTAssertEqual(GateIntentLogic.appName(from: " Instagram "), "Instagram")
    }

    func testEvaluateGroupMode() {
        let blocked = GateIntentLogic.evaluate(appParameter: nil, snapshot: snapshot(), closedAutomationDetected: false, now: now)
        XCTAssertTrue(blocked.isGroup)
        XCTAssertEqual(blocked.accessName, AppKey.group)
        XCTAssertEqual(blocked.trackingName, AppKey.groupDisplayName)
        XCTAssertTrue(blocked.showsGate)
        XCTAssertFalse(blocked.tracksSessionTime)

        let unlocked = GateIntentLogic.evaluate(appParameter: "", snapshot: snapshot(grants: [grant(AppKey.group)]),
                                                closedAutomationDetected: true, now: now)
        XCTAssertFalse(unlocked.showsGate)
        XCTAssertTrue(unlocked.tracksSessionTime)
    }

    func testEvaluateNamedApp() {
        let evaluation = GateIntentLogic.evaluate(appParameter: "TikTok", snapshot: snapshot(blocked: ["tiktok"]),
                                                  closedAutomationDetected: false, now: now)
        XCTAssertFalse(evaluation.isGroup)
        XCTAssertEqual(evaluation.trackingName, "TikTok")
        XCTAssertTrue(evaluation.showsGate)
        // A named app that isn't on the per-app list is allowed.
        XCTAssertFalse(GateIntentLogic.evaluate(appParameter: "Notes", snapshot: snapshot(), closedAutomationDetected: false, now: now).showsGate)
    }

    func testRouting() {
        XCTAssertEqual(GateIntentLogic.routing(showsGate: false, canContinueInForeground: true), .stayInBackground)
        XCTAssertEqual(GateIntentLogic.routing(showsGate: false, canContinueInForeground: false), .stayInBackground)
        XCTAssertEqual(GateIntentLogic.routing(showsGate: true, canContinueInForeground: true), .continueInForeground)
        XCTAssertEqual(GateIntentLogic.routing(showsGate: true, canContinueInForeground: false), .notifyOnly)
        XCTAssertEqual(GateIntentLogic.closedTrackingName(appParameter: nil), AppKey.groupDisplayName)
        XCTAssertEqual(GateIntentLogic.closedTrackingName(appParameter: "YouTube"), "YouTube")
    }

    // MARK: Small types

    func testPendingGateRequestFreshness() {
        let request = PendingGateRequest(appName: nil, requestedAt: now)
        XCTAssertTrue(request.isFresh(at: now.addingTimeInterval(30)))
        XCTAssertFalse(request.isFresh(at: now.addingTimeInterval(PendingGateRequest.lifetime + 1)))
    }

    func testRunStatsAndStatus() {
        let store = SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
        XCTAssertFalse(QuickSetupStatus(store.quickSetupRunStats).isDetected)
        store.recordGateIntentRun(at: now)
        store.recordGateIntentRun(at: now.addingTimeInterval(5))
        store.recordAppClosedIntentRun(at: now.addingTimeInterval(9))
        let status = QuickSetupStatus(store.quickSetupRunStats)
        XCTAssertTrue(status.isDetected)
        XCTAssertTrue(status.tracksUsageTime)
        XCTAssertEqual(status.gateRuns, 2)
        XCTAssertEqual(status.lastGateRunAt, now.addingTimeInterval(5))
        XCTAssertTrue(store.groupBlockingEnabled)
        store.groupBlockingEnabled = false
        XCTAssertFalse(store.accessSnapshot().groupBlockingEnabled)
    }

    func testPostUnlockAction() {
        let url = URL(string: "instagram://")!
        XCTAssertEqual(PostUnlockAction(outcome: .granted(appName: "Instagram", minutes: 10, until: now, costLife: false, reopenURL: url)),
                       .reopen(appName: "Instagram", url: url))
        let swipe = PostUnlockAction(outcome: .granted(appName: "Blocked apps", minutes: 10, until: now, costLife: false, reopenURL: nil))
        XCTAssertEqual(swipe, .swipeBack(minutes: 10, until: now))
        XCTAssertEqual(swipe?.message, "Unlocked for 10 min — swipe back to your app")
        XCTAssertNil(PostUnlockAction(outcome: .declined))
        XCTAssertNil(PostUnlockAction(outcome: nil))
    }

    func testGroupTargetHelpers() {
        let target = ChatTarget.blockedAppsGroup(origin: .gate)
        XCTAssertTrue(target.isBlockedAppsGroup)
        XCTAssertTrue(UnlockSubject.blockedAppsGroup.isBlockedAppsGroup)
        XCTAssertFalse(UnlockSubject.appName("Instagram").isBlockedAppsGroup)
        XCTAssertNil(target.reopenURL)
        XCTAssertEqual(target.trackingName, AppKey.groupDisplayName)
        XCTAssertEqual(target.displayName, AppKey.groupSubjectName)
    }

    func testSetupModeDefaults() {
        XCTAssertEqual(SetupMode.recommended, QuickSetup.isAvailable ? .quick : .perApp)
        XCTAssertFalse(QuickSetup.steps.isEmpty)
        XCTAssertTrue(QuickSetup.steps.contains { $0.contains(QuickSetup.gateActionName) })
        XCTAssertTrue(QuickSetup.optionalTrackingSteps.contains { $0.contains(QuickSetup.closedActionName) })
    }

    // MARK: Engine + ViewModel flows (Shortcuts engine, in-memory store)

    @MainActor
    private func makeEnvironment() -> AppEnvironment {
        let shared = SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
        let env = AppEnvironment(container: BobblyModelContainer.make(inMemory: true), shared: shared, isPreview: true)
        env.chat.typingDelay = .zero
        env.engines.shortcuts.postsNotifications = false
        return env
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func testGroupGrantFromEngineCountsOnceAndNamesTheBucket() throws {
        let env = makeEnvironment()
        let unlocks = try env.engines.grantUnlocks([.appName("Instagram"), .blockedAppsGroup], displayName: "Instagram", minutes: 5)
        XCTAssertEqual(Set(unlocks.map(\.displayName)), ["Instagram", AppKey.groupDisplayName])
        XCTAssertEqual(env.shared.unlocksToday(), 1)
        XCTAssertTrue(env.engines.decision(forAppNamed: AppKey.group).isAllowed)
        XCTAssertTrue(unlocks.contains { $0.subject.isBlockedAppsGroup })
    }

    @MainActor
    func testDeepLinkWithoutAppAndPendingRequestOpenGroupGate() async {
        let env = makeEnvironment()
        env.handle(url: URL(string: "bobbly://gate")!)
        guard case .gate(let target) = env.router.cover else { return XCTFail("gate not presented") }
        XCTAssertTrue(target.isBlockedAppsGroup)

        env.router.dismissCover()
        env.shared.pendingGateRequest = PendingGateRequest(appName: nil, requestedAt: Date())
        env.consumePendingGateRequest()
        guard case .gate(let again) = env.router.cover else { return XCTFail("pending gate not presented") }
        XCTAssertTrue(again.isBlockedAppsGroup)
        XCTAssertNil(env.shared.pendingGateRequest)

        // Stale requests are dropped.
        env.router.dismissCover()
        env.shared.pendingGateRequest = PendingGateRequest(appName: nil, requestedAt: Date().addingTimeInterval(-600))
        env.consumePendingGateRequest()
        XCTAssertNil(env.router.cover)
    }

    @MainActor
    func testGroupGateCopyAndChatUnlock() async {
        let env = makeEnvironment()
        let gate = env.makeGateViewModel(target: .blockedAppsGroup(origin: .gate))
        gate.onAppear()
        XCTAssertTrue(gate.isGroupMode)
        XCTAssertFalse(gate.isAllowedNow)
        XCTAssertEqual(gate.headline, "That app is blocked")
        XCTAssertEqual(env.tracker.interruptionCount(in: UsageAggregator.lastDays(1)), 1)

        gate.talkToBobbly()
        XCTAssertTrue(env.chat.isGroupConversation)
        await waitUntil { env.chat.quickReplies.contains { $0.kind == .reason(.work) } }
        env.chat.select(env.chat.quickReplies.first { $0.kind == .reason(.work) }!)
        await waitUntil { env.chat.outcome != nil }

        guard case .swipeBack(let minutes, _)? = env.chat.postUnlockAction else {
            return XCTFail("expected swipe-back, got \(String(describing: env.chat.postUnlockAction))")
        }
        XCTAssertEqual(minutes, 15)
        XCTAssertTrue(env.engines.decision(forAppNamed: AppKey.group).isAllowed)
        XCTAssertEqual(env.engines.status.activeUnlocks.first?.displayName, AppKey.groupDisplayName)

        let reopened = env.makeGateViewModel(target: .blockedAppsGroup(origin: .gate))
        reopened.refresh()
        XCTAssertEqual(reopened.headline, "Your apps are unlocked")
        if case .swipeBack? = reopened.postUnlockAction {} else { XCTFail("gate should offer swipe back") }
    }

    @MainActor
    func testChatTabUnlockAlsoOpensGroupWhenQuickSetupIsActive() async {
        let env = makeEnvironment()
        env.shared.recordGateIntentRun()   // the automation has run → quick setup is guarding
        XCTAssertTrue(env.isQuickSetupBlocking)
        env.chat.start(target: nil)
        await waitUntil { env.chat.acceptsFreeText }
        env.chat.draft = "Instagram"
        env.chat.send()
        await waitUntil { env.chat.quickReplies.contains { $0.kind == .reason(.school) } }
        env.chat.select(env.chat.quickReplies.first { $0.kind == .reason(.school) }!)
        await waitUntil { env.chat.outcome != nil }
        XCTAssertTrue(env.engines.decision(forAppNamed: AppKey.group).isAllowed)
        XCTAssertTrue(env.engines.decision(forAppNamed: "Instagram").isAllowed)
        XCTAssertEqual(env.shared.unlocksToday(), 1)
    }

    @MainActor
    func testHomeShowsProtectingForQuickSetup() {
        let env = makeEnvironment()   // Shortcuts engine (Screen Time never requested)
        env.home.refresh()
        XCTAssertEqual(env.home.protection, .setupNeeded)
        env.shared.recordGateIntentRun()
        env.home.refresh()
        XCTAssertTrue(env.home.isGroupBlocking)
        XCTAssertEqual(env.home.protection, .protecting(blockedCount: 0))
        XCTAssertEqual(env.home.blockingSummary, "Blocking the apps in your Bobbly Gate automation")
        env.shared.groupBlockingEnabled = false
        env.home.refresh()
        XCTAssertEqual(env.home.protection, .setupNeeded)
    }

    @MainActor
    func testGateOpenLoggingWithoutCloseAutomationCountsOpensNotTime() {
        let env = makeEnvironment()
        let start = Date().addingTimeInterval(-600)
        env.tracker.logGateOpen(appName: AppKey.groupDisplayName, tracksTime: false, at: start)
        env.tracker.logGateOpen(appName: AppKey.groupDisplayName, tracksTime: false, at: start.addingTimeInterval(60))
        let today = UsageAggregator.lastDays(1)
        let summary = UsageAggregator.summaries(env.tracker.records(in: today), range: today)
        XCTAssertEqual(summary.first?.appName, AppKey.groupDisplayName)
        XCTAssertEqual(summary.first?.opens, 2)
        XCTAssertEqual(summary.first?.totalMinutes ?? -1, 0, accuracy: 0.001)

        // With the optional "Is Closed" automation, real time is tracked.
        env.tracker.logGateOpen(appName: AppKey.groupDisplayName, tracksTime: true, at: start.addingTimeInterval(120))
        env.tracker.logClosed(appName: GateIntentLogic.closedTrackingName(appParameter: nil), at: start.addingTimeInterval(420))
        let after = UsageAggregator.summaries(env.tracker.records(in: today), range: today)
        XCTAssertEqual(after.first?.totalMinutes ?? 0, 5, accuracy: 0.01)
    }
}
