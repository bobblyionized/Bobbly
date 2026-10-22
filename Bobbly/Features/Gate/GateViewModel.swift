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
    /// Always `nil` in group mode (Bobbly doesn't know which app opened).
    var reopenURL: URL? { target.reopenURL }

    /// Quick-setup group mode: the automation covers several apps and can't say
    /// which one opened. Copy talks about "that app" / "your blocked apps".
    var isGroupMode: Bool { target.isBlockedAppsGroup }

    /// While an unlock is running: how to get back to the app —
    /// `.reopen(…)` → "Open Instagram", `.swipeBack(…)` → "swipe back to your app".
    var postUnlockAction: PostUnlockAction? {
        guard let until = unlockedUntil else { return nil }
        if let url = reopenURL { return .reopen(appName: appName, url: url) }
        let minutes = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
        return .swipeBack(minutes: minutes, until: until)
    }

    // MARK: Actions

    /// Evaluates access and logs one blocked interruption.
    func onAppear() {
        refresh()
        if !decision.isAllowed && !didLogInterruption {
            didLogInterruption = true
            // CheckAccessIntent / the Gate intent usually logged this attempt a moment ago.
            env.tracker.logInterruptionIfNew(appName: target.trackingName, source: .gate)
            env.home.refresh()
        }
    }

    func refresh() {
        let now = Date()
        decision = env.engines.decision(forAppNamed: isGroupMode ? AppKey.group : appName, now: now)
        unlocksToday = env.shared.unlocksToday(now: now)
        if isGroupMode {
            applyGroupCopy()
            return
        }
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

    /// Group-mode copy (the opened app is unknown).
    private func applyGroupCopy() {
        switch decision {
        case .allowed(.unlocked(let until)):
            unlockedUntil = until
            headline = "Your apps are unlocked"
            message = "Swipe back to your app. Bobbly locks them again when the time is up."
        case .allowed:
            unlockedUntil = nil
            headline = "You're good to go"
            message = "Bobbly isn't blocking your apps right now. Swipe back to your app."
        case .blocked(.studySession(let name)):
            unlockedUntil = nil
            headline = "You're studying"
            message = "\(name) is running, so your distracting apps stay closed until it ends."
        case .blocked(.blockedApp):
            unlockedUntil = nil
            headline = "That app is blocked"
            message = unlocksToday == 0
                ? "It's one of the apps you asked Bobbly to guard. No unlocks yet today. Nice!"
                : "It's one of the apps you asked Bobbly to guard. You've unlocked \(unlocksToday) time\(unlocksToday == 1 ? "" : "s") today."
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
