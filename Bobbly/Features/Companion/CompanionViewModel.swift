//  CompanionViewModel.swift
//  Bobbly/Features/Companion — Bobbly detail: mood, lives, streak, rules.

import Foundation
import Observation

@Observable
@MainActor
final class CompanionViewModel {
    unowned let env: AppEnvironment

    /// What Bobbly is "saying" in the speech bubble (changes on `pet()`).
    private(set) var speech: String = ""
    /// Increments on every `pet()`; animate a bounce on change.
    private(set) var petCount: Int = 0

    @ObservationIgnored private var rng = SystemRandomNumberGenerator()

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Derived

    var snapshot: CompanionSnapshot { env.companion.snapshot }
    var freeUnlocksPerDay: Int { env.preferences.dailyFreeUnlocks }

    /// How Bobbly works, for the info section.
    var rules: [String] {
        [
            "Bobbly has \(CompanionRules.maxLives) lives every day. They refill at midnight — always tomorrow.",
            "You get \(freeUnlocksPerDay) free unlocks a day; each unlock past that costs a life.",
            "Focus time (study sessions) and saying no in chat make Bobbly happier.",
            "Emergency unblocks are always free and never cost a life.",
            "Your streak grows for every day Bobbly ends with at least one life.",
        ]
    }

    /// Seconds until lives refill.
    func timeUntilReset(at now: Date = Date()) -> TimeInterval {
        max(0, snapshot.resetsAt.timeIntervalSince(now))
    }

    // MARK: Actions

    func onAppear() {
        env.companion.refresh()
        speech = snapshot.line
    }

    /// Tap on Bobbly: a cute reaction line (no game effect).
    func pet() {
        petCount += 1
        let reactions: [String]
        switch snapshot.tier {
        case .thriving, .happy: reactions = ["Hehe, that tickles!", "Yay! 💛", "Again! Again!"]
        case .okay: reactions = ["Thanks, I needed that.", "That helps a little."]
        case .sad: reactions = ["Aww… thank you.", "A study session would cheer me up."]
        case .exhausted: reactions = ["Zzz… *happy snore*", "Tomorrow we try again, okay?"]
        }
        speech = reactions.randomElement(using: &rng) ?? snapshot.line
    }
}
