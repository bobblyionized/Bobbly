import XCTest
@testable import Bobbly

final class CompanionRulesTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: d, hour: hour))!
    }

    func testFreshState() {
        let values = CompanionValues.fresh(day: day(1))
        XCTAssertEqual(values.mood, 60)
        XCTAssertEqual(values.lives, 3)
    }

    func testUnlocksWithinAllowanceCostMoodNotLives() {
        let start = CompanionValues.fresh(day: day(1))
        let result = CompanionRules.applyUnlock(start, unlocksBefore: 0, freeUnlocks: 3)
        XCTAssertFalse(result.costLife)
        XCTAssertEqual(result.values.lives, 3)
        XCTAssertEqual(result.values.mood, 60 - CompanionRules.unlockMoodCost)
    }

    func testUnlockPastAllowanceCostsALifeAndFloorsAtZero() {
        var values = CompanionValues.fresh(day: day(1))
        for n in 3..<8 {
            let result = CompanionRules.applyUnlock(values, unlocksBefore: n, freeUnlocks: 3)
            values = result.values
            XCTAssertEqual(result.costLife, n < 6, "unlock #\(n)")
        }
        XCTAssertEqual(values.lives, 0)
        XCTAssertEqual(values.livesLostToday, 3)
        XCTAssertGreaterThanOrEqual(values.mood, 0)
        XCTAssertEqual(CompanionMood(mood: values.mood, lives: values.lives), .exhausted)
    }

    func testFocusRaisesMoodAndClamps() {
        var values = CompanionValues.fresh(day: day(1))
        values = CompanionRules.applyFocus(values, minutes: 50)
        XCTAssertEqual(values.mood, 70)
        XCTAssertEqual(values.focusMinutesToday, 50)
        values = CompanionRules.applyFocus(values, minutes: 10_000)
        XCTAssertEqual(values.mood, 100)
    }

    func testRollDayRefillsAndExtendsStreak() {
        var values = CompanionValues.fresh(day: day(1))
        values = CompanionRules.applyUnlock(values, unlocksBefore: 5, freeUnlocks: 3).values
        values.currentStreak = 4
        values.bestStreak = 4
        let next = CompanionRules.rollDay(values, now: day(2, hour: 8), calendar: calendar)
        XCTAssertEqual(next.lives, 3)
        XCTAssertEqual(next.mood, CompanionRules.startingMood)
        XCTAssertEqual(next.livesLostToday, 0)
        XCTAssertEqual(next.currentStreak, 5)
        XCTAssertEqual(next.bestStreak, 5)
        XCTAssertEqual(next.day, day(2))
    }

    func testRollDayBreaksStreakWhenOutOfLives() {
        var values = CompanionValues.fresh(day: day(1))
        values.lives = 0
        values.currentStreak = 9
        values.bestStreak = 9
        let next = CompanionRules.rollDay(values, now: day(2, hour: 1), calendar: calendar)
        XCTAssertEqual(next.currentStreak, 0)
        XCTAssertEqual(next.bestStreak, 9)
    }

    func testRollDaySameDayIsNoOp() {
        let values = CompanionValues.fresh(day: day(1))
        XCTAssertEqual(CompanionRules.rollDay(values, now: day(1, hour: 23), calendar: calendar), values)
    }

    func testOverDailyLimitCostsALifeEvenWithinFreeUnlocks() {
        let start = CompanionValues.fresh(day: day(1))
        let result = CompanionRules.applyUnlock(start, unlocksBefore: 0, freeUnlocks: 3, overDailyLimit: true)
        XCTAssertTrue(result.costLife)
        XCTAssertEqual(result.values.lives, 2)
    }

    func testResistedBonusIsRateLimited() {
        let t0 = day(1, hour: 10)
        var values = CompanionValues.fresh(day: day(1))
        values = CompanionRules.applyResistedTemptation(values, now: t0)
        XCTAssertEqual(values.mood, 64)
        // Within the cooldown: no extra mood.
        values = CompanionRules.applyResistedTemptation(values, now: t0.addingTimeInterval(60))
        XCTAssertEqual(values.mood, 64)
        // After the cooldown: counts again, up to the daily maximum.
        var t = t0
        for _ in 0..<10 {
            t = t.addingTimeInterval(CompanionRules.resistedCooldown + 1)
            values = CompanionRules.applyResistedTemptation(values, now: t)
        }
        XCTAssertEqual(values.resistedToday, CompanionRules.maxResistedPerDay)
        XCTAssertEqual(values.mood, 60 + CompanionRules.resistedTemptationBonus * CompanionRules.maxResistedPerDay)
    }

    func testRollDayResetsResistedAndPassiveCounters() {
        var values = CompanionValues.fresh(day: day(1))
        values.resistedToday = 6
        values.passiveFocusMinutesToday = 200
        values.lastResistedAt = day(1, hour: 9)
        let next = CompanionRules.rollDay(values, now: day(2, hour: 9), calendar: calendar)
        XCTAssertEqual(next.resistedToday, 0)
        XCTAssertEqual(next.passiveFocusMinutesToday, 0)
        XCTAssertNil(next.lastResistedAt)
    }

    func testPassiveFocusMinutesSubtractsUnlockWindows() {
        let since = day(1, hour: 10)
        let now = day(1, hour: 11)
        let unlock = DateInterval(start: day(1, hour: 10).addingTimeInterval(15 * 60), duration: 10 * 60)
        let overlapping = DateInterval(start: day(1, hour: 10).addingTimeInterval(20 * 60), duration: 10 * 60)
        XCTAssertEqual(CompanionRules.passiveFocusMinutes(since: since, now: now, excluded: [], calendar: calendar), 60)
        // 10:15–10:25 and 10:20–10:30 merge to 15 minutes.
        XCTAssertEqual(CompanionRules.passiveFocusMinutes(since: since, now: now, excluded: [unlock, overlapping], calendar: calendar), 45)
    }

    func testPassiveFocusIsClippedToTodayAndCapped() {
        // Since yesterday evening: only counts from midnight, and at most 3 h.
        XCTAssertEqual(CompanionRules.passiveFocusMinutes(since: day(1, hour: 20), now: day(2, hour: 1), excluded: [], calendar: calendar), 60)
        XCTAssertEqual(CompanionRules.passiveFocusMinutes(since: day(2, hour: 0), now: day(2, hour: 9), excluded: [], calendar: calendar), 180)
        XCTAssertEqual(CompanionRules.passiveFocusMinutes(since: nil, now: day(2, hour: 9), excluded: [], calendar: calendar), 0)
    }

    func testApplyPassiveFocusAccumulatesAndCaps() {
        var values = CompanionValues.fresh(day: day(1))
        values = CompanionRules.applyPassiveFocus(values, minutes: 10, now: day(1, hour: 10))
        XCTAssertEqual(values.mood, 60) // 10 min < 15
        values = CompanionRules.applyPassiveFocus(values, minutes: 10, now: day(1, hour: 11))
        XCTAssertEqual(values.mood, 61) // 20 min → +1
        XCTAssertEqual(values.lastFocusCreditAt, day(1, hour: 11))
        values = CompanionRules.applyPassiveFocus(values, minutes: 10_000, now: day(1, hour: 12))
        XCTAssertEqual(values.mood, 60 + CompanionRules.maxPassiveMoodPerDay)
        values = CompanionRules.applyPassiveFocus(values, minutes: 600, now: day(1, hour: 13))
        XCTAssertEqual(values.mood, 60 + CompanionRules.maxPassiveMoodPerDay)
    }

    func testMoodTiers() {
        XCTAssertEqual(CompanionMood(mood: 90, lives: 3), .thriving)
        XCTAssertEqual(CompanionMood(mood: 60, lives: 1), .happy)
        XCTAssertEqual(CompanionMood(mood: 40, lives: 2), .okay)
        XCTAssertEqual(CompanionMood(mood: 10, lives: 2), .sad)
        XCTAssertEqual(CompanionMood(mood: 99, lives: 0), .exhausted)
    }
}
