//  CompanionRules.swift
//  Bobbly/Engine/Companion — pure rules for Bobbly's mood, lives and streak.
//
//  • Mood 0–100, starts each day at 60 ("always tomorrow").
//  • 3 lives per day. Unlocking past the daily free allowance — or past an
//    app's daily time limit — costs a life.
//  • Focus raises mood: study minutes (+1 per 5 min), protected time with no
//    unlock running (+1 per 15 min, max +16/day), saying no in chat (+4, at
//    most every 10 min and 6×/day so the Gate's "Go back" can't be farmed).
//  • Streak = consecutive finished days that ended with at least one life.

import Foundation

/// Value copy of `CompanionState`.
struct CompanionValues: Equatable, Sendable {
    var mood: Int
    var lives: Int
    /// Start of the day these counters belong to.
    var day: Date
    var focusMinutesToday: Int
    var livesLostToday: Int
    var currentStreak: Int
    var bestStreak: Int
    /// Up to when protected time has been credited (prevents double counting).
    var lastFocusCreditAt: Date?
    /// Protected (passive) focus minutes credited today.
    var passiveFocusMinutesToday: Int = 0
    /// "Said no" bonuses granted today (rate-limited).
    var resistedToday: Int = 0
    var lastResistedAt: Date?

    static func fresh(day: Date) -> CompanionValues {
        CompanionValues(mood: CompanionRules.startingMood, lives: CompanionRules.maxLives, day: day,
                        focusMinutesToday: 0, livesLostToday: 0, currentStreak: 0, bestStreak: 0,
                        lastFocusCreditAt: nil)
    }
}

/// Bobbly's visible mood tier (drives face + copy).
enum CompanionMood: String, CaseIterable, Sendable {
    case thriving
    case happy
    case okay
    case sad
    case exhausted

    init(mood: Int, lives: Int) {
        if lives <= 0 { self = .exhausted; return }
        switch mood {
        case 85...: self = .thriving
        case 60..<85: self = .happy
        case 35..<60: self = .okay
        default: self = .sad
        }
    }
}

enum CompanionRules {
    static let maxLives = 3
    static let startingMood = 60
    static let moodRange = 0...100

    /// +1 mood per this many study (active focus) minutes.
    static let focusMinutesPerMoodPoint = 5
    /// +1 mood per this many protected (passive) minutes.
    static let passiveMinutesPerMoodPoint = 15
    /// Passive focus can add at most this much mood per day.
    static let maxPassiveMoodPerDay = 16
    /// One protected-time credit never covers more than this (e.g. overnight).
    static let maxPassiveCreditPerCheck: TimeInterval = 3 * 60 * 60

    static let unlockMoodCost = 3
    static let lifeLossMoodCost = 12
    static let resistedTemptationBonus = 4
    static let resistedCooldown: TimeInterval = 10 * 60
    static let maxResistedPerDay = 6
    static let studyCompletedBonus = 6
    static let studyEndedEarlyCost = 6

    /// Applies the daily reset if `now` is on a later day than `values.day`.
    static func rollDay(_ values: CompanionValues, now: Date, calendar: Calendar = .current) -> CompanionValues {
        let today = calendar.startOfDay(for: now)
        guard today > values.day else { return values }
        let elapsedDays = max(1, calendar.dateComponents([.day], from: values.day, to: today).day ?? 1)

        var next = CompanionValues.fresh(day: today)
        // The day that just finished counts if Bobbly still had a life.
        // Days the app wasn't opened at all count as kept (no unlocks possible).
        if values.lives > 0 {
            next.currentStreak = values.currentStreak + elapsedDays
        } else {
            next.currentStreak = elapsedDays - 1
        }
        next.bestStreak = max(values.bestStreak, next.currentStreak)
        next.lastFocusCreditAt = values.lastFocusCreditAt
        return next
    }

    static func applyFocus(_ values: CompanionValues, minutes: Int) -> CompanionValues {
        guard minutes > 0 else { return values }
        var next = values
        next.focusMinutesToday += minutes
        next.mood = clampMood(values.mood + minutes / focusMinutesPerMoodPoint)
        return next
    }

    /// - Parameters:
    ///   - unlocksBefore: unlocks already granted today, not counting this one.
    ///   - freeUnlocks: daily allowance that doesn't cost a life.
    ///   - overDailyLimit: the app is already past its daily time limit.
    /// - Returns: new values and whether a life was lost.
    static func applyUnlock(_ values: CompanionValues, unlocksBefore: Int, freeUnlocks: Int,
                            overDailyLimit: Bool = false) -> (values: CompanionValues, costLife: Bool) {
        var next = values
        next.mood = clampMood(values.mood - unlockMoodCost)
        let costsLife = overDailyLimit || unlocksBefore >= freeUnlocks
        if costsLife && next.lives > 0 {
            next.lives -= 1
            next.livesLostToday += 1
            next.mood = clampMood(next.mood - lifeLossMoodCost)
            return (next, true)
        }
        return (next, false)
    }

    /// Emergency unblocks are always free: no mood or life cost.
    static func applyEmergency(_ values: CompanionValues) -> CompanionValues { values }

    /// The user backed out in chat / at the gate. Rate-limited.
    static func applyResistedTemptation(_ values: CompanionValues, now: Date) -> CompanionValues {
        if let last = values.lastResistedAt, now.timeIntervalSince(last) < resistedCooldown { return values }
        guard values.resistedToday < maxResistedPerDay else { return values }
        var next = values
        next.mood = clampMood(values.mood + resistedTemptationBonus)
        next.resistedToday += 1
        next.lastResistedAt = now
        return next
    }

    static func applyStudyCompleted(_ values: CompanionValues, minutes: Int) -> CompanionValues {
        var next = applyFocus(values, minutes: minutes)
        next.mood = clampMood(next.mood + studyCompletedBonus)
        return next
    }

    static func applyStudyEndedEarly(_ values: CompanionValues, minutes: Int) -> CompanionValues {
        var next = applyFocus(values, minutes: minutes)
        next.mood = clampMood(next.mood - studyEndedEarlyCost)
        return next
    }

    // MARK: Passive focus

    /// Protected minutes between `since` (clipped to today and to
    /// `maxPassiveCreditPerCheck`) and `now`, minus time covered by `excluded`
    /// windows (running unlocks, emergency unblocks).
    static func passiveFocusMinutes(since: Date?, now: Date, excluded: [DateInterval],
                                    calendar: Calendar = .current) -> Int {
        let dayStart = calendar.startOfDay(for: now)
        let earliest = max(dayStart, now.addingTimeInterval(-maxPassiveCreditPerCheck))
        let start = max(since ?? now, earliest)
        guard now > start else { return 0 }
        let window = DateInterval(start: start, end: now)

        // Merge excluded windows that overlap the credit window, then subtract.
        let clipped = excluded.compactMap { $0.intersection(with: window) }.sorted { $0.start < $1.start }
        var covered: TimeInterval = 0
        var cursor = window.start
        for interval in clipped {
            let s = max(interval.start, cursor)
            if interval.end > s {
                covered += interval.end.timeIntervalSince(s)
                cursor = interval.end
            }
        }
        return max(0, Int((window.duration - covered) / 60))
    }

    /// Credits protected minutes (mood +1 per 15, capped per day) and moves the
    /// credit marker to `now`. Pass `minutes: 0` when nothing was protected.
    static func applyPassiveFocus(_ values: CompanionValues, minutes: Int, now: Date) -> CompanionValues {
        var next = values
        next.lastFocusCreditAt = now
        guard minutes > 0 else { return next }
        let before = values.passiveFocusMinutesToday / passiveMinutesPerMoodPoint
        next.passiveFocusMinutesToday += minutes
        let after = min(maxPassiveMoodPerDay, next.passiveFocusMinutesToday / passiveMinutesPerMoodPoint)
        next.mood = clampMood(values.mood + max(0, after - min(before, maxPassiveMoodPerDay)))
        return next
    }

    static func clampMood(_ mood: Int) -> Int {
        min(moodRange.upperBound, max(moodRange.lowerBound, mood))
    }
}
