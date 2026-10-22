//  GateViewModel.swift
//  Bobbly/Features/Gate — the block screen opened by bobbly://gate?app=…
//  (Shortcuts engine). Shows Bobbly, "Talk to Bobbly" and "Go back".

import Foundation
import Observation

@Observable
@MainActor
final class GateViewModel {
    unowned let env: AppEnvironment

    /// The app being gated (subject is `.appName` for Shortcuts links).
    let target: ChatTarget

    /// Current access decision for `target` (may already be allowed, e.g. an unlock is running).
    private(set) var decision: AccessDecision = .blocked(.blockedApp)
    /// Big title, e.g. "Instagram is blocked".
    private(set) var headline: String = ""
    /// Supporting line, e.g. "You've unlocked 2 times today." / study-session reason.
    private(set) var message: String = ""
    private(set) var unlocksToday: Int = 0
    /// If an unlock for this app is running: its expiry (UI can show "Open Instagram · 7 min left").
    private(set) var unlockedUntil: Date?

    @ObservationIgnored private var didLogInterruption = false

    init(env: AppEnvironment, target: ChatTarget) {
        self.env = env
        self.target = target
    }

    // MARK: Derived

    var companion: CompanionSnapshot { env.companion.snapshot }
    var appName: String { target.displayName }
    var isAllowedNow: Bool { decision.isAllowed }
    /// Re-opens the app (Shortcuts engine) when it's allowed. Use with `openURL`.
    var reopenURL: URL? { target.reopenURL }

    // MARK: Actions

    /// Evaluates access and logs one blocked interruption.
    func onAppear() {
        refresh()
        if !decision.isAllowed && !didLogInterruption {
            didLogInterruption = true
            // CheckAccessIntent usually logged this attempt a moment ago.
            env.tracker.logInterruptionIfNew(appName: appName, source: .gate)
            env.home.refresh()
        }
    }

    func refresh() {
        let now = Date()
        decision = env.engines.decision(forAppNamed: appName, now: now)
        unlocksToday = env.shared.unlocksToday(now: now)
        switch decision {
        case .allowed(.unlocked(let until)):
            unlockedUntil = until
            headline = "\(appName) is unlocked"
            message = "You still have time left. Enjoy it mindfully."
        case .allowed:
            unlockedUntil = nil
            headline = "\(appName) is open"
            message = "Bobbly isn't blocking \(appName) right now."
        case .blocked(.studySession(let name)):
            unlockedUntil = nil
            headline = "You're studying"
            message = "\(name) is running, and \(appName) isn't on its whitelist."
        case .blocked(.blockedApp):
            unlockedUntil = nil
            headline = "\(appName) is blocked"
            message = unlocksToday == 0
                ? "No unlocks yet today. Nice!"
                : "You've unlocked apps \(unlocksToday) time\(unlocksToday == 1 ? "" : "s") today."
        }
    }

    /// Dismisses the gate and starts the chat about this app.
    func talkToBobbly() {
        env.router.dismissCover()
        env.openChat(target)
    }

    /// "Go back": counts as resisting; closes the gate.
    func goBack() {
        if !decision.isAllowed { env.companion.recordResistedTemptation() }
        env.router.dismissCover()
    }

    func openEmergency() {
        env.presentSheet(.emergency)
    }
}
