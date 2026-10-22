import XCTest
@testable import Bobbly

final class SharedStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> SharedStore {
        SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
    }

    func testGrantsPersistAndPrune() {
        let store = makeStore()
        let expired = UnlockGrant(appKey: "a", tokenData: nil, displayName: "A", grantedAt: now, expiresAt: now.addingTimeInterval(-1))
        let live = UnlockGrant(appKey: "b", tokenData: nil, displayName: "B", grantedAt: now, expiresAt: now.addingTimeInterval(60))
        store.addGrant(expired)
        store.addGrant(live)
        XCTAssertEqual(store.activeGrants(at: now).map(\.id), [live.id])
        XCTAssertEqual(store.pruneExpiredGrants(now: now).map(\.id), [expired.id])
        XCTAssertEqual(store.grants.map(\.id), [live.id])
    }

    func testAddGrantReplacesSameID() {
        let store = makeStore()
        var grant = UnlockGrant(appKey: "a", tokenData: nil, displayName: "A", grantedAt: now, expiresAt: now.addingTimeInterval(60))
        store.addGrant(grant)
        grant.expiresAt = now.addingTimeInterval(120)
        store.addGrant(grant)
        XCTAssertEqual(store.grants.count, 1)
        XCTAssertEqual(store.grants.first?.expiresAt, now.addingTimeInterval(120))
    }

    func testBlockedAppKeysAreNormalizedAndDeduplicated() {
        let store = makeStore()
        store.blockedAppKeys = ["Instagram", " instagram ", "TikTok"]
        XCTAssertEqual(store.blockedAppKeys, ["instagram", "tiktok"])
    }

    func testDailyCountersRollOver() {
        let store = makeStore()
        store.incrementUnlocks(now: now)
        store.incrementUnlocks(now: now)
        store.incrementInterruptions(now: now)
        XCTAssertEqual(store.unlocksToday(now: now), 2)
        XCTAssertEqual(store.interruptionsToday(now: now), 1)
        let tomorrow = now.addingTimeInterval(86_400 * 1.5)
        XCTAssertEqual(store.unlocksToday(now: tomorrow), 0)
        store.incrementUnlocks(now: tomorrow)
        XCTAssertEqual(store.unlocksToday(now: tomorrow), 1)
        XCTAssertEqual(store.interruptionsToday(now: tomorrow), 0)
    }

    func testEmergencyAndStudyRoundTrip() {
        let store = makeStore()
        store.emergencyUntil = now.addingTimeInterval(60)
        XCTAssertTrue(store.isEmergencyActive(at: now))
        XCTAssertFalse(store.isEmergencyActive(at: now.addingTimeInterval(61)))

        let study = ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "S", selectionData: nil,
                                allowedAppKeys: ["notes"], startedAt: now, endsAt: nil)
        store.activeStudy = study
        XCTAssertEqual(store.activeStudy, study)
        store.activeStudy = nil
        XCTAssertNil(store.activeStudy)
    }

    func testAccessSnapshotReflectsStore() {
        let store = makeStore()
        store.blockedAppKeys = ["Reddit"]
        store.isDetached = true
        let snapshot = store.accessSnapshot()
        XCTAssertTrue(snapshot.isDetached)
        XCTAssertEqual(snapshot.blockedAppKeys, ["reddit"])
    }

    func testResetAllClearsEverything() {
        let store = makeStore()
        store.isDetached = true
        store.blockedAppKeys = ["x"]
        store.resetAll()
        XCTAssertFalse(store.isDetached)
        XCTAssertTrue(store.blockedAppKeys.isEmpty)
        XCTAssertNil(store.engineKind)
    }

    func testMonitorLogIsBounded() {
        let store = makeStore()
        for i in 0..<60 { store.appendLog("line \(i)", now: now) }
        XCTAssertEqual(store.monitorLog.count, 40)
        XCTAssertTrue(store.monitorLog.last?.hasSuffix("line 59") ?? false)
    }

    func testAppKeyNormalization() {
        XCTAssertEqual(AppKey.normalize("  Café  "), "cafe")
        XCTAssertEqual(AppKey.normalize("YouTube"), "youtube")
    }
}
