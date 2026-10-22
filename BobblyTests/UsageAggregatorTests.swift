import XCTest
@testable import Bobbly

final class UsageAggregatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    private func record(_ app: String, _ start: Date, minutes: Double?) -> UsageRecord {
        UsageRecord(appName: app, start: start, end: minutes.map { start.addingTimeInterval($0 * 60) })
    }

    func testDailyTotalsSplitAcrossMidnight() {
        let records = [record("Instagram", date(10, 23, 30), minutes: 60)]
        let range = DateInterval(start: date(10, 0), end: date(12, 0))
        let points = UsageAggregator.dailyTotals(records, range: range, perApp: false, now: date(20, 0), calendar: calendar)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].minutes, 30, accuracy: 0.01)
        XCTAssertEqual(points[1].minutes, 30, accuracy: 0.01)
    }

    func testOpenSessionIsCappedAndNeverPastNow() {
        let open = record("TikTok", date(10, 9), minutes: nil)
        XCTAssertEqual(UsageAggregator.effectiveEnd(of: open, now: date(10, 9, 20)), date(10, 9, 20))
        XCTAssertEqual(UsageAggregator.effectiveEnd(of: open, now: date(11, 9)),
                       date(10, 9).addingTimeInterval(UsageAggregator.openSessionCap))
    }

    func testPerAppTotalsAndSummaries() {
        let records = [
            record("Instagram", date(10, 9), minutes: 10),
            record("instagram", date(10, 12), minutes: 20),
            record("TikTok", date(10, 13), minutes: 5),
        ]
        let range = DateInterval(start: date(10, 0), end: date(11, 0))
        let summaries = UsageAggregator.summaries(records, range: range, now: date(20, 0))
        XCTAssertEqual(summaries.first?.appKey, "instagram")
        XCTAssertEqual(summaries.first?.totalMinutes ?? 0, 30, accuracy: 0.01)
        XCTAssertEqual(summaries.first?.opens, 2)
        XCTAssertEqual(summaries.last?.appKey, "tiktok")
    }

    func testSearchComputesStats() throws {
        let records = [
            record("YouTube", date(10, 9), minutes: 30),
            record("YouTube", date(10, 20), minutes: 10),
            record("YouTube", date(12, 8), minutes: 50),
            record("Instagram", date(11, 8), minutes: 99),
        ]
        let range = DateInterval(start: date(10, 0), end: date(13, 0)) // 3 days
        let result = try XCTUnwrap(UsageAggregator.search(records, appQuery: "you", range: range, now: date(20, 0), calendar: calendar))
        XCTAssertEqual(result.appName, "YouTube")
        XCTAssertEqual(result.totalMinutes, 90, accuracy: 0.01)
        XCTAssertEqual(result.averageMinutesPerDay, 30, accuracy: 0.01)
        XCTAssertEqual(result.longestSessionMinutes, 50, accuracy: 0.01)
        XCTAssertEqual(result.totalOpens, 3)
        XCTAssertEqual(result.opensPerDay, 1, accuracy: 0.01)
        XCTAssertEqual(result.daily.count, 3)
        XCTAssertEqual(result.daily[1].minutes, 0, accuracy: 0.01)
    }

    func testSearchWithNoMatchReturnsNil() {
        let records = [record("YouTube", date(10, 9), minutes: 30)]
        let range = DateInterval(start: date(10, 0), end: date(11, 0))
        XCTAssertNil(UsageAggregator.search(records, appQuery: "netflix", range: range, now: date(20, 0), calendar: calendar))
        XCTAssertNil(UsageAggregator.search(records, appQuery: "  ", range: range, now: date(20, 0), calendar: calendar))
    }

    func testMatchingPrefersPrefix() {
        let names = ["Snapchat", "Instagram", "Pinterest", "Instagram"]
        XCTAssertEqual(UsageAggregator.matchingAppNames(names, query: "in"), ["Instagram", "Pinterest"])
    }

    func testTimeSavedAgainstLimits() {
        let records = [
            record("Instagram", date(10, 9), minutes: 20),
            record("Instagram", date(11, 9), minutes: 40),
        ]
        let range = DateInterval(start: date(10, 0), end: date(12, 0))
        let saved = UsageAggregator.timeSavedMinutes(records, limits: ["instagram": 30], range: range, now: date(20, 0), calendar: calendar)
        XCTAssertEqual(saved, 10, accuracy: 0.01) // day 1: 30-20, day 2: over limit → 0
    }
}
