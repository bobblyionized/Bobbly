import XCTest
@testable import Bobbly

/// Mutable clock shared with the engine under test.
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}

/// Engine + isolated store + controllable clock.
@MainActor
private struct SUT {
    let engine: ShortcutsEngine
    let store: SharedStore
    let clock: TestClock

    init() {
        store = SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
        let clock = TestClock()
        self.clock = clock
        engine = ShortcutsEngine(shared: store, clock: { clock.now }, postsNotifications: false)
        try? engine.block(BlockList(selection: .init(), appNames: ["Instagram", "TikTok"]))
    }

    func allowed(_ app: String) -> Bool {
        engine.decision(forAppNamed: app, now: clock.now).isAllowed
    }

    func decision(_ app: String) -> AccessDecision {
        engine.decision(forAppNamed: app, now: clock.now)
    }
}

final class ShortcutsEngineTests: XCTestCase {

    @MainActor
    func testBlockedAppsAreDeniedOthersAllowed() {
        let sut = SUT()
        XCTAssertFalse(sut.allowed("Instagram"))
        XCTAssertFalse(sut.allowed("  instagram "))
        XCTAssertTrue(sut.allowed("Notes"))
        XCTAssertEqual(sut.decision("Notes"), .allowed(.notBlocked))
    }

    @MainActor
    func testUnlockAllowsUntilExpiryThenRelocks() throws {
        let sut = SUT()
        try sut.engine.grantUnlock(.appName("Instagram"), displayName: "Instagram", minutes: 10)
        XCTAssertTrue(sut.allowed("Instagram"))
        XCTAssertFalse(sut.allowed("TikTok"))
        XCTAssertEqual(sut.store.unlocksToday(now: sut.clock.now), 1)

        sut.clock.advance(minutes: 9.9)
        XCTAssertTrue(sut.allowed("Instagram"))
        sut.clock.advance(minutes: 0.2)
        XCTAssertFalse(sut.allowed("Instagram"))
        XCTAssertTrue(sut.engine.status.activeUnlocks.isEmpty)
    }

    @MainActor
    func testRegrantReplacesExistingGrant() throws {
        let sut = SUT()
        try sut.engine.grantUnlock(.appName("Instagram"), displayName: "Instagram", minutes: 10)
        try sut.engine.grantUnlock(.appName("instagram"), displayName: "Instagram", minutes: 5)
        XCTAssertEqual(sut.store.grants.count, 1)
        sut.clock.advance(minutes: 6)
        XCTAssertFalse(sut.allowed("Instagram"))
    }

    @MainActor
    func testRevokeRelocksImmediately() throws {
        let sut = SUT()
        let unlock = try sut.engine.grantUnlock(.appName("Instagram"), displayName: "Instagram", minutes: 10)
        sut.engine.revokeUnlock(id: unlock.id)
        XCTAssertFalse(sut.allowed("Instagram"))
    }

    @MainActor
    func testStudySubjectCannotBeGranted() {
        let sut = SUT()
        XCTAssertThrowsError(try sut.engine.grantUnlock(.studySession, displayName: "Study", minutes: 5))
    }

    @MainActor
    func testEmergencyAllowsEverythingUntilItEnds() throws {
        let sut = SUT()
        try sut.engine.emergencyUnblockAll(minutes: 30)
        XCTAssertTrue(sut.allowed("Instagram"))
        sut.clock.advance(minutes: 31)
        XCTAssertFalse(sut.allowed("Instagram"))
    }

    @MainActor
    func testEndEmergencyEarly() throws {
        let sut = SUT()
        try sut.engine.emergencyUnblockAll(minutes: 30)
        sut.engine.endEmergency()
        XCTAssertFalse(sut.allowed("Instagram"))
    }

    @MainActor
    func testStudySessionBlocksEverythingExceptWhitelist() throws {
        let sut = SUT()
        let study = ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "Homework", selectionData: nil,
                                allowedAppKeys: ["notes"], startedAt: sut.clock.now, endsAt: sut.clock.now.addingTimeInterval(3600))
        try sut.engine.startStudy(study)
        XCTAssertTrue(sut.allowed("Notes"))
        XCTAssertEqual(sut.decision("YouTube"), .blocked(.studySession(whitelistName: "Homework")))
        sut.clock.advance(minutes: 61)
        XCTAssertTrue(sut.allowed("YouTube"))
        XCTAssertFalse(sut.allowed("Instagram"))
    }

    @MainActor
    func testUnlockOverridesStudySession() throws {
        let sut = SUT()
        let study = ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "Study", selectionData: nil,
                                allowedAppKeys: [], startedAt: sut.clock.now, endsAt: nil)
        try sut.engine.startStudy(study)
        try sut.engine.grantUnlock(.appName("YouTube"), displayName: "YouTube", minutes: 5)
        XCTAssertTrue(sut.allowed("YouTube"))
        XCTAssertFalse(sut.allowed("Notes"))
        sut.engine.endStudy()
        XCTAssertTrue(sut.allowed("Notes"))
    }

    @MainActor
    func testDetachAllowsEverythingAndReattachRestores() async throws {
        let sut = SUT()
        try sut.engine.grantUnlock(.appName("TikTok"), displayName: "TikTok", minutes: 5)
        let report = await sut.engine.detach()
        XCTAssertEqual(report.engine, .shortcuts)
        XCTAssertFalse(report.manualSteps.isEmpty)
        XCTAssertTrue(sut.allowed("Instagram"))
        XCTAssertEqual(sut.decision("Instagram"), .allowed(.detached))
        XCTAssertTrue(sut.store.grants.isEmpty)

        sut.engine.reattach()
        XCTAssertFalse(sut.allowed("Instagram"))
    }

    @MainActor
    func testDailyCounterResetsNextDay() throws {
        let sut = SUT()
        try sut.engine.grantUnlock(.appName("Instagram"), displayName: "Instagram", minutes: 1)
        XCTAssertEqual(sut.store.unlocksToday(now: sut.clock.now), 1)
        XCTAssertEqual(sut.store.unlocksToday(now: sut.clock.now.addingTimeInterval(86_400 * 2)), 0)
    }

    @MainActor
    func testMultiAppGrantCountsAsOneUnlock() throws {
        let sut = SUT()
        let unlocks = try sut.engine.grantUnlocks([.appName("Instagram"), .appName("TikTok"), .appName("instagram")],
                                                  displayName: "2 apps", minutes: 5)
        XCTAssertEqual(unlocks.count, 2)
        XCTAssertEqual(sut.store.unlocksToday(now: sut.clock.now), 1)
        XCTAssertTrue(sut.allowed("Instagram"))
        XCTAssertTrue(sut.allowed("TikTok"))
        XCTAssertEqual(Set(unlocks.map(\.displayName)), ["Instagram", "TikTok"])
    }

    @MainActor
    func testInvalidSubjectInBatchChangesNothing() {
        let sut = SUT()
        XCTAssertThrowsError(try sut.engine.grantUnlocks([.appName("Instagram"), .studySession], displayName: "x", minutes: 5))
        XCTAssertTrue(sut.store.grants.isEmpty)
        XCTAssertEqual(sut.store.unlocksToday(now: sut.clock.now), 0)
        XCTAssertThrowsError(try sut.engine.grantUnlocks([], displayName: "x", minutes: 5))
    }

    @MainActor
    func testStatusReflectsState() throws {
        let sut = SUT()
        XCTAssertEqual(sut.engine.status.kind, .shortcuts)
        XCTAssertEqual(sut.engine.status.blockedAppCount, 2)
        try sut.engine.grantUnlock(.appName("Instagram"), displayName: "Instagram", minutes: 5)
        try sut.engine.emergencyUnblockAll(minutes: 10)
        let status = sut.engine.status
        XCTAssertEqual(status.activeUnlocks.first?.displayName, "Instagram")
        XCTAssertTrue(status.isEmergencyActive(at: sut.clock.now))
    }

    func testAccessPolicyWhitelistAndExpiredStudy() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let study = ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "S", selectionData: nil,
                                allowedAppKeys: ["Khan Academy"], startedAt: now.addingTimeInterval(-60),
                                endsAt: now.addingTimeInterval(60))
        let snapshot = AccessSnapshot(isDetached: false, emergencyUntil: nil, blockedAppKeys: [], grants: [], study: study)
        XCTAssertEqual(AccessPolicy.decide(appName: "khan academy", snapshot: snapshot, now: now), .allowed(.whitelisted))
        XCTAssertEqual(AccessPolicy.decide(appName: "Reddit", snapshot: snapshot, now: now), .blocked(.studySession(whitelistName: "S")))
        XCTAssertEqual(AccessPolicy.decide(appName: "Reddit", snapshot: snapshot, now: now.addingTimeInterval(120)), .allowed(.notBlocked))
        XCTAssertEqual(AccessPolicy.decide(appName: "Reddit", snapshot: .empty, now: now), .allowed(.notBlocked))
    }

    func testAccessPolicyPrecedence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let grant = UnlockGrant(appKey: "instagram", tokenData: nil, displayName: "Instagram",
                                grantedAt: now, expiresAt: now.addingTimeInterval(600))
        var snapshot = AccessSnapshot(isDetached: false, emergencyUntil: nil, blockedAppKeys: ["instagram"],
                                      grants: [grant], study: nil)
        XCTAssertEqual(AccessPolicy.decide(appName: "Instagram", snapshot: snapshot, now: now),
                       .allowed(.unlocked(until: grant.expiresAt)))
        snapshot.emergencyUntil = now.addingTimeInterval(60)
        XCTAssertEqual(AccessPolicy.decide(appName: "Instagram", snapshot: snapshot, now: now),
                       .allowed(.emergency(until: now.addingTimeInterval(60))))
        snapshot.isDetached = true
        XCTAssertEqual(AccessPolicy.decide(appName: "Instagram", snapshot: snapshot, now: now), .allowed(.detached))
    }
}
