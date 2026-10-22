//  CompanionService.swift
//  Bobbly/Engine/Companion — persists `CompanionState` and publishes a
//  `CompanionSnapshot` for the UI. All mutations go through `CompanionRules`.

import Foundation
import Observation
import SwiftData

/// What every screen showing Bobbly needs.
struct CompanionSnapshot: Equatable, Sendable {
    /// 0...100
    var mood: Int
    var lives: Int
    var maxLives: Int
    var tier: CompanionMood
    var focusMinutesToday: Int
    var livesLostToday: Int
    var currentStreak: Int
    var bestStreak: Int
    /// Next local midnight (lives refill, mood resets).
    var resetsAt: Date
    /// A short line Bobbly "says" for the current tier.
    var line: String

    /// 0...1 for progress rings.
    var moodFraction: Double { Double(mood) / 100 }

    static let placeholder = CompanionSnapshot(mood: 60, lives: 3, maxLives: 3, tier: .happy, focusMinutesToday: 0,
                                               livesLostToday: 0, currentStreak: 0, bestStreak: 0,
                                               resetsAt: Date().addingTimeInterval(86_400), line: "Hi! I'm Bobbly.")
}

@Observable
@MainActor
final class CompanionService {
    private(set) var snapshot: CompanionSnapshot = .placeholder

    private let context: ModelContext
    private let shared: SharedStore
    private let calendar: Calendar

    init(context: ModelContext, shared: SharedStore = .shared, calendar: Calendar = .current) {
        self.context = context
        self.shared = shared
        self.calendar = calendar
        refresh()
    }

    // MARK: - Mutations

    /// Applies the daily reset if needed and republishes. Call on foreground.
    func refresh(now: Date = Date()) {
        mutate(now: now) { $0 }
    }

    /// Records a chat-granted unlock. - Returns: whether it cost a life.
    @discardableResult
    func recordUnlock(unlocksBefore: Int, overDailyLimit: Bool = false, now: Date = Date()) -> Bool {
        var lost = false
        let free = shared.dailyFreeUnlocks
        mutate(now: now) { values in
            let result = CompanionRules.applyUnlock(values, unlocksBefore: unlocksBefore, freeUnlocks: free,
                                                    overDailyLimit: overDailyLimit)
            lost = result.costLife
            return result.values
        }
        return lost
    }

    /// "Said no" (chat decline / Gate › Go back). Rate-limited by the rules.
    func recordResistedTemptation(now: Date = Date()) {
        mutate(now: now) { CompanionRules.applyResistedTemptation($0, now: now) }
    }

    /// Credits protected time since the last credit as passive focus.
    /// - Parameters:
    ///   - isProtecting: blocking is set up and active (not detached, something blocked).
    ///   - excluded: windows when apps were unlocked (chat grants, emergencies).
    func creditPassiveFocus(isProtecting: Bool, excluded: [DateInterval], now: Date = Date()) {
        let calendar = self.calendar
        mutate(now: now) { values in
            guard isProtecting else { return CompanionRules.applyPassiveFocus(values, minutes: 0, now: now) }
            let minutes = CompanionRules.passiveFocusMinutes(since: values.lastFocusCreditAt, now: now,
                                                             excluded: excluded, calendar: calendar)
            return CompanionRules.applyPassiveFocus(values, minutes: minutes, now: now)
        }
    }

    func recordFocus(minutes: Int, now: Date = Date()) {
        mutate(now: now) { CompanionRules.applyFocus($0, minutes: minutes) }
    }

    func recordStudyFinished(minutes: Int, endedEarly: Bool, now: Date = Date()) {
        mutate(now: now) {
            endedEarly ? CompanionRules.applyStudyEndedEarly($0, minutes: minutes)
                       : CompanionRules.applyStudyCompleted($0, minutes: minutes)
        }
    }

    // MARK: - Private

    private func mutate(now: Date, _ change: (CompanionValues) -> CompanionValues) {
        let state = loadOrCreate(now: now)
        var values = CompanionRules.rollDay(state.values, now: now, calendar: calendar)
        values = change(values)
        state.values = values
        try? context.save()

        shared.companionMood = values.mood
        shared.companionLives = values.lives
        snapshot = Self.makeSnapshot(values, now: now, calendar: calendar)
    }

    private func loadOrCreate(now: Date) -> CompanionState {
        let key = CompanionState.mainKey
        let descriptor = FetchDescriptor<CompanionState>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let state = CompanionState(values: .fresh(day: calendar.startOfDay(for: now)))
        context.insert(state)
        return state
    }

    static func makeSnapshot(_ values: CompanionValues, now: Date, calendar: Calendar = .current) -> CompanionSnapshot {
        let tier = CompanionMood(mood: values.mood, lives: values.lives)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return CompanionSnapshot(mood: values.mood, lives: values.lives, maxLives: CompanionRules.maxLives, tier: tier,
                                 focusMinutesToday: values.focusMinutesToday, livesLostToday: values.livesLostToday,
                                 currentStreak: values.currentStreak, bestStreak: values.bestStreak,
                                 resetsAt: tomorrow, line: CompanionLines.line(for: tier, seed: values.mood &+ values.lives))
    }
}

/// Short things Bobbly says per mood tier.
enum CompanionLines {
    static let bank: [CompanionMood: [String]] = [
        .thriving: ["I feel amazing. Look at us go!", "Best. Day. Ever.", "We're unstoppable today."],
        .happy: ["Hi! I'm doing pretty great.", "Thanks for keeping me company.", "Feeling good, friend."],
        .okay: ["I'm okay. Could use some focus time.", "Let's do something nice for us.", "Hanging in there."],
        .sad: ["I'm feeling a bit droopy…", "Maybe a little study session?", "I miss the focused you."],
        .exhausted: ["I'm out of lives today. Tomorrow's a fresh start.", "Always tomorrow. Let's rest.", "Zzz… new lives at midnight."],
    ]

    static func line(for tier: CompanionMood, seed: Int) -> String {
        let lines = bank[tier] ?? ["Hi!"]
        return lines[abs(seed) % lines.count]
    }
}
