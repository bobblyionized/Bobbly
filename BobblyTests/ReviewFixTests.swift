import XCTest
import DeviceActivity
@testable import Bobbly

/// Regression tests for the reviewer's findings.
final class ReviewFixTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> SharedStore {
        SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
    }

    // MARK: ShieldPolicy never unshields on unreadable state (#2)

    func testShieldPolicySkipsWhenStateUnreadable() {
        XCTAssertEqual(ShieldPolicy.action(engineKind: nil, isDetached: false, isEmergencyActive: false,
                                           appGroupAvailable: true, requireAppGroup: true),
                       .skip(reason: "no engine recorded"))
        XCTAssertEqual(ShieldPolicy.action(engineKind: .familyControls, isDetached: false, isEmergencyActive: false,
                                           appGroupAvailable: false, requireAppGroup: true),
                       .skip(reason: "App Group unavailable"))
        // The app process may act on its own store even without the App Group.
        XCTAssertEqual(ShieldPolicy.action(engineKind: .familyControls, isDetached: false, isEmergencyActive: false,
                                           appGroupAvailable: false, requireAppGroup: false), .apply)
    }

    func testShieldPolicyClearsOnlyWhenExplicit() {
        XCTAssertEqual(ShieldPolicy.action(engineKind: .shortcuts, isDetached: false, isEmergencyActive: false,
                                           appGroupAvailable: true, requireAppGroup: true), .clear(reason: "Shortcuts engine"))
        XCTAssertEqual(ShieldPolicy.action(engineKind: .familyControls, isDetached: true, isEmergencyActive: false,
                                           appGroupAvailable: true, requireAppGroup: true), .clear(reason: "detached"))
        XCTAssertEqual(ShieldPolicy.action(engineKind: .familyControls, isDetached: false, isEmergencyActive: true,
                                           appGroupAvailable: true, requireAppGroup: true), .clear(reason: "emergency"))
        XCTAssertEqual(ShieldPolicy.action(engineKind: .familyControls, isDetached: false, isEmergencyActive: false,
                                           appGroupAvailable: true, requireAppGroup: true), .apply)
    }

    // MARK: Token revocation (#3)

    func testInvalidateTokensClearsSelectionTokenGrantsAndStudy() {
        let store = makeStore()
        let tokenGrant = UnlockGrant(appKey: nil, tokenData: Data([1]), displayName: "T", grantedAt: now, expiresAt: now.addingTimeInterval(60))
        let nameGrant = UnlockGrant(appKey: "x", tokenData: nil, displayName: "X", grantedAt: now, expiresAt: now.addingTimeInterval(60))
        store.addGrant(tokenGrant)
        store.addGrant(nameGrant)
        let study = ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "S", selectionData: Data([9]),
                                allowedAppKeys: [], startedAt: now, endsAt: nil)
        store.activeStudy = study

        store.invalidateTokens(now: now)

        XCTAssertEqual(store.grants.map(\.id), [nameGrant.id])
        XCTAssertNil(store.activeStudy)
        XCTAssertEqual(store.studyEndRecord(for: study.sessionID)?.reason, .detached)
        XCTAssertEqual(store.tokensRevokedAt, now)
        XCTAssertTrue(store.blockedSelection.applicationTokens.isEmpty)
    }

    // MARK: Detach rule shared by app and Siri (#7)

    func testDetachRule() {
        XCTAssertTrue(DetachRule.usesFamilyControls(engineKind: .familyControls, isAuthorized: false))
        XCTAssertTrue(DetachRule.usesFamilyControls(engineKind: .shortcuts, isAuthorized: true))
        XCTAssertTrue(DetachRule.usesFamilyControls(engineKind: nil, isAuthorized: true))
        XCTAssertFalse(DetachRule.usesFamilyControls(engineKind: .shortcuts, isAuthorized: false))
        XCTAssertFalse(DetachRule.usesFamilyControls(engineKind: nil, isAuthorized: false))
    }

    // MARK: Chat never presents empty turns (#4)

    func testIgnoredInputYieldsEmptyTurn() {
        var engine = ChatEngine(context: .relaxed, seed: 1)
        _ = engine.start(subjectName: "X")
        _ = engine.respond(to: .text("homework"))
        XCTAssertTrue(engine.respond(to: .cooldownElapsed).isEmpty)
        XCTAssertTrue(ChatTurn.none.isEmpty)
        XCTAssertFalse(ChatTurn(acceptsFreeText: false, decision: .emergency).isEmpty)
    }

    // MARK: Study end resolution (#5)

    @MainActor
    func testResolveEndNeverBeforeStartAndDetachedIsNotCompleted() {
        let start = now
        let detached = StudyEndRecord(sessionID: UUID(), endedAt: start.addingTimeInterval(-500), reason: .detached)
        let a = StudyViewModel.resolveEnd(of: start, plannedEnd: nil, record: detached, now: start.addingTimeInterval(600))
        XCTAssertEqual(a.endedAt, start)
        XCTAssertFalse(a.completed)

        let completed = StudyEndRecord(sessionID: UUID(), endedAt: start.addingTimeInterval(1500), reason: .completed)
        let b = StudyViewModel.resolveEnd(of: start, plannedEnd: start.addingTimeInterval(1500), record: completed, now: start.addingTimeInterval(3000))
        XCTAssertEqual(b.endedAt, start.addingTimeInterval(1500))
        XCTAssertTrue(b.completed)

        // No record, plan not reached (e.g. cleared elsewhere): ended now, not completed.
        let c = StudyViewModel.resolveEnd(of: start, plannedEnd: start.addingTimeInterval(9000), record: nil, now: start.addingTimeInterval(60))
        XCTAssertEqual(c.endedAt, start.addingTimeInterval(60))
        XCTAssertFalse(c.completed)

        // No record, plan passed: completed at the planned end.
        let d = StudyViewModel.resolveEnd(of: start, plannedEnd: start.addingTimeInterval(60), record: nil, now: start.addingTimeInterval(600))
        XCTAssertEqual(d.endedAt, start.addingTimeInterval(60))
        XCTAssertTrue(d.completed)
    }

    // MARK: Interruption counting (#6)

    func testShieldHitsOnSameAppAreOneAttempt() {
        let store = makeStore()
        XCTAssertTrue(store.recordShieldInterruption(attemptKey: "app:A", now: now))
        XCTAssertFalse(store.recordShieldInterruption(attemptKey: "app:A", now: now.addingTimeInterval(30)))
        XCTAssertTrue(store.recordShieldInterruption(attemptKey: "app:B", now: now.addingTimeInterval(40)))
        XCTAssertTrue(store.recordShieldInterruption(attemptKey: "app:A", now: now.addingTimeInterval(40 + SharedStore.shieldHitDedupWindow)))
        XCTAssertEqual(store.interruptionsToday(now: now), 3)
    }

    func testInterruptionsAreKeptPerDay() {
        let store = makeStore()
        let dayTwo = now.addingTimeInterval(86_400 * 1.5)
        store.incrementInterruptions(now: now)
        store.incrementInterruptions(now: now)
        store.incrementInterruptions(now: dayTwo)
        XCTAssertEqual(store.interruptionsByDay[SharedStore.dayKey(now)], 2)
        XCTAssertEqual(store.interruptionsByDay[SharedStore.dayKey(dayTwo)], 1)
        XCTAssertEqual(store.interruptionsToday(now: dayTwo), 1)
    }

    func testOldInterruptionDaysArePruned() {
        let store = makeStore()
        store.incrementInterruptions(now: now)
        store.incrementInterruptions(now: now.addingTimeInterval(86_400 * Double(SharedStore.interruptionHistoryDays + 2)))
        XCTAssertEqual(store.interruptionsByDay.count, 1)
    }

    func testIngestPendingDeltasPerDay() {
        let shared = ["100": 3, "200": 5, "300": 1]
        let imported = ["100": 3, "200": 2]
        XCTAssertEqual(InterruptionIngest.pending(shared: shared, imported: imported),
                       [.init(dayKey: "200", delta: 3), .init(dayKey: "300", delta: 1)])
        XCTAssertEqual(InterruptionIngest.date(forDayKey: "0", now: Date(timeIntervalSince1970: 3600)),
                       Date(timeIntervalSince1970: 3600))
        XCTAssertEqual(InterruptionIngest.date(forDayKey: "0", now: Date(timeIntervalSince1970: 86_400)),
                       Date(timeIntervalSince1970: 12 * 3600))
    }

    // MARK: Unique trigger names (risk)

    func testTriggerNamesAreUniquePerInstance() {
        let a = DeviceActivityName.bobblyEmergency()
        let b = DeviceActivityName.bobblyEmergency()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.isBobblyEmergencyTrigger)
        XCTAssertFalse(a.isBobblyStudyTrigger)
        XCTAssertTrue(DeviceActivityName.bobblyStudy().isBobblyStudyTrigger)
        XCTAssertFalse(DeviceActivityName.bobblyDaily.isBobblyEmergencyTrigger)
    }

    // MARK: Router hand-off (risk)

    @MainActor
    func testRouterSequencesSheetAndCover() async {
        let router = AppRouter()
        router.presentTutorial()
        XCTAssertEqual(router.cover, .tutorial)

        router.present(.emergency) // cover up → dismissed first
        XCTAssertNil(router.cover)
        XCTAssertNil(router.sheet)
        try? await Task.sleep(for: AppRouter.modalHandoffDelay + .milliseconds(200))
        XCTAssertEqual(router.sheet, .emergency)

        router.presentTutorial() // sheet up → dismissed first
        XCTAssertNil(router.sheet)
        router.showTab(.home) // cancels the pending cover
        try? await Task.sleep(for: AppRouter.modalHandoffDelay + .milliseconds(200))
        XCTAssertNil(router.cover)
    }
}
