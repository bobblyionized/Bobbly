import XCTest
import DeviceActivity
@testable import Bobbly

final class MonitorAndScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> SharedStore {
        SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
    }

    // MARK: Schedules

    func testTriggerUsesTimeOnlyComponentsAndSatisfiesMinimumLength() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23, minute: 52, second: 30))!
        let (start, end) = ActivitySchedules.triggerComponents(at: date, calendar: calendar)

        XCTAssertNil(start.year); XCTAssertNil(start.month); XCTAssertNil(start.day)
        XCTAssertNil(end.year); XCTAssertNil(end.month); XCTAssertNil(end.day)
        XCTAssertEqual(start.hour, 23); XCTAssertEqual(start.minute, 52); XCTAssertEqual(start.second, 30)
        // 16 minutes later wraps past midnight.
        XCTAssertEqual(end.hour, 0); XCTAssertEqual(end.minute, 8); XCTAssertEqual(end.second, 30)
        XCTAssertGreaterThanOrEqual(ActivitySchedules.triggerLength, ActivitySchedules.minimumInterval)
    }

    func testTriggerDateNeverInThePast() {
        XCTAssertEqual(ActivitySchedules.triggerDate(for: now.addingTimeInterval(600), now: now), now.addingTimeInterval(600))
        XCTAssertEqual(ActivitySchedules.triggerDate(for: now.addingTimeInterval(-30), now: now),
                       now.addingTimeInterval(ActivitySchedules.minimumLeadTime))
    }

    func testUnlockActivityNameRoundTrip() {
        let id = UUID()
        let name = DeviceActivityName.bobblyUnlock(id)
        XCTAssertEqual(name.bobblyUnlockGrantID, id)
        XCTAssertTrue(name.isBobblyActivity)
        XCTAssertNil(DeviceActivityName.bobblyEmergency().bobblyUnlockGrantID)
        XCTAssertNil(DeviceActivityName("someone.else").bobblyUnlockGrantID)
        XCTAssertFalse(DeviceActivityName("someone.else").isBobblyActivity)
    }

    // MARK: Monitor logic

    func testDueUnlockIsRemovedOnceAndIdempotent() {
        let store = makeStore()
        let grant = UnlockGrant(appKey: "instagram", tokenData: nil, displayName: "Instagram",
                                grantedAt: now.addingTimeInterval(-600), expiresAt: now)
        store.addGrant(grant)

        XCTAssertEqual(MonitorLogic.handle(.bobblyUnlock(grant.id), shared: store, now: now), .unlocksEnded([grant]))
        XCTAssertTrue(store.grants.isEmpty)
        XCTAssertEqual(MonitorLogic.handle(.bobblyUnlock(grant.id), shared: store, now: now), .none)
    }

    func testEarlyTriggerWithinToleranceStillRelocks() {
        let store = makeStore()
        let grant = UnlockGrant(appKey: "x", tokenData: nil, displayName: "X", grantedAt: now, expiresAt: now.addingTimeInterval(60))
        store.addGrant(grant)
        XCTAssertEqual(MonitorLogic.handle(.bobblyUnlock(grant.id), shared: store, now: now), .unlocksEnded([grant]))
    }

    func testOneTriggerRelocksEveryDueGrantButKeepsLaterOnes() {
        let store = makeStore()
        let a = UnlockGrant(appKey: nil, tokenData: Data([1]), displayName: "A", grantedAt: now, expiresAt: now)
        let b = UnlockGrant(appKey: nil, tokenData: Data([2]), displayName: "B", grantedAt: now, expiresAt: now)
        let later = UnlockGrant(appKey: "c", tokenData: nil, displayName: "C", grantedAt: now, expiresAt: now.addingTimeInterval(900))
        store.addGrant(a); store.addGrant(b); store.addGrant(later)
        XCTAssertEqual(MonitorLogic.handle(.bobblyUnlock(a.id), shared: store, now: now), .unlocksEnded([a, b]))
        XCTAssertEqual(store.grants.map(\.id), [later.id])
    }

    func testNotYetDueUnlockIsLeftAlone() {
        let store = makeStore()
        let grant = UnlockGrant(appKey: "x", tokenData: nil, displayName: "X", grantedAt: now, expiresAt: now.addingTimeInterval(600))
        store.addGrant(grant)
        XCTAssertEqual(MonitorLogic.handle(.bobblyUnlock(grant.id), shared: store, now: now), .none)
        XCTAssertEqual(store.grants.count, 1)
    }

    func testEmergencyEndsOnlyWhenDue() {
        let store = makeStore()
        store.emergencyUntil = now.addingTimeInterval(3600) // extended meanwhile
        XCTAssertEqual(MonitorLogic.handle(.bobblyEmergency(), shared: store, now: now), .none)
        XCTAssertNotNil(store.emergencyUntil)

        store.emergencyUntil = now.addingTimeInterval(-5)
        XCTAssertEqual(MonitorLogic.handle(.bobblyEmergency(), shared: store, now: now), .emergencyEnded)
        XCTAssertNil(store.emergencyUntil)
    }

    func testTimedStudyEndsAndRecordsEnd() {
        let store = makeStore()
        let end = now.addingTimeInterval(-1)
        store.activeStudy = ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "Homework",
                                        selectionData: nil, allowedAppKeys: [], startedAt: now.addingTimeInterval(-3000), endsAt: end)
        XCTAssertEqual(MonitorLogic.handle(.bobblyStudy(), shared: store, now: now), .studyEnded(whitelistName: "Homework"))
        XCTAssertNil(store.activeStudy)
        XCTAssertEqual(store.lastStudyEndedAt, end)
    }

    func testOpenEndedStudyIsNeverEndedByMonitor() {
        let store = makeStore()
        store.activeStudy = ActiveStudy(sessionID: UUID(), whitelistID: UUID(), whitelistName: "Open",
                                        selectionData: nil, allowedAppKeys: [], startedAt: now, endsAt: nil)
        XCTAssertEqual(MonitorLogic.handle(.bobblyStudy(), shared: store, now: now), .none)
        XCTAssertNotNil(store.activeStudy)
    }

    func testDailyActivityIsNoOp() {
        XCTAssertEqual(MonitorLogic.handle(.bobblyDaily, shared: makeStore(), now: now), .none)
    }
}
