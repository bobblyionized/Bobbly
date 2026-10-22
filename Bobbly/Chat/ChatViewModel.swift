//  ChatViewModel.swift
//  Bobbly/Chat — drives ChatView: runs ChatEngine, animates Bobbly typing,
//  runs cooldowns and applies decisions (grant / end study / decline / emergency).

import Foundation
import Observation
import FamilyControls

@Observable
@MainActor
final class ChatViewModel {
    unowned let env: AppEnvironment

    // MARK: State (read by the view)

    /// Transcript, oldest first.
    private(set) var messages: [ChatMessage] = []
    /// Chips under the last Bobbly message. Empty = none.
    private(set) var quickReplies: [QuickReply] = []
    /// Show the typing indicator bubble.
    private(set) var isBobblyTyping = false
    /// Text field binding.
    var draft: String = ""
    /// `false` = hide/disable the text field (decisions, cooldowns).
    private(set) var acceptsFreeText = true
    private(set) var inputPlaceholder = "Type a message…"
    /// Running cooldown (render a countdown ring with `progress(at:)`).
    private(set) var cooldown: ChatCooldown?
    /// The sentence to type to unlock anyway (also shown as a `.commitment` bubble).
    private(set) var commitmentPhrase: String?
    /// Final result card; `nil` while the conversation is ongoing.
    private(set) var outcome: ChatOutcome?
    /// What we're talking about (nil = chat started from the tab without a target).
    private(set) var target: ChatTarget?
    private(set) var phase: ChatPhase = .idle

    /// FamilyControls only: a grant was decided but the app token is unknown
    /// (chat started from the tab). UI presents `FamilyActivityPicker` bound to
    /// `appSelection`. When the picker closes (this flips to `false`) the grant is
    /// completed automatically — confirmed if apps were picked, otherwise
    /// cancelled. Calling `confirmAppSelection()` / `cancelAppSelection()`
    /// explicitly also works.
    var needsAppSelection = false {
        didSet {
            guard oldValue, !needsAppSelection, pendingGrantMinutes != nil else { return }
            if appSelection.applicationTokens.isEmpty {
                cancelAppSelection()
            } else {
                confirmAppSelection()
            }
        }
    }
    var appSelection = FamilyActivitySelection()

    /// Delay before Bobbly's lines appear (tests set `.zero`).
    @ObservationIgnored var typingDelay: Duration = .milliseconds(700)

    @ObservationIgnored private var engine = ChatEngine(context: .relaxed)
    @ObservationIgnored private var pendingGrantMinutes: Int?
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    @ObservationIgnored private var turnTask: Task<Void, Never>?

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Derived

    var companion: CompanionSnapshot { env.companion.snapshot }

    var canSend: Bool {
        acceptsFreeText && !isBobblyTyping && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasConversation: Bool { !messages.isEmpty }

    // MARK: Actions

    /// Starts a conversation if none is running (Chat tab opened directly).
    /// Checks `phase` (set synchronously by `start`) rather than `messages`
    /// (filled asynchronously), so a gate/shield-targeted chat that is still
    /// rendering its first lines is never wiped.
    func onAppear() {
        if phase == .idle { start(target: nil) }
    }

    /// Starts a new conversation about `target` (`nil` = Bobbly asks which app).
    func start(target: ChatTarget?) {
        cancelTasks()
        self.target = target
        messages = []
        outcome = nil
        cooldown = nil
        commitmentPhrase = nil
        pendingGrantMinutes = nil
        needsAppSelection = false
        draft = ""

        engine = ChatEngine(context: makeContext(appName: target?.subject.appKey == nil ? nil : target?.displayName))
        let turn = engine.start(
            subjectName: target?.displayName,
            isStudySession: target?.subject == .studySession,
            knownApps: knownAppNames()
        )
        present(turn, typing: false)
    }

    /// Sends `draft` as the user's message.
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        messages.append(ChatMessage(sender: .user, text: text))
        present(respond(.text(text)), typing: true)
    }

    /// Taps a quick-reply chip.
    func select(_ reply: QuickReply) {
        guard !isBobblyTyping else { return }
        if reply.kind == .startOver {
            // Full reset through `start`: clears the old target, outcome card,
            // commitment and pending grant, so a new conversation can never
            // unlock the previous app. A study-session chat stays about the study.
            start(target: target?.subject == .studySession ? target : nil)
            return
        }
        messages.append(ChatMessage(sender: .user, text: reply.title))
        present(respond(.quickReply(reply)), typing: true)
    }

    /// Runs the engine; once the app is known (chat started without a target),
    /// refreshes the strictness context with that app's daily-limit usage.
    private func respond(_ input: ChatInput) -> ChatTurn {
        let wasAskingApp = engine.phase == .askingApp
        let turn = engine.respond(to: input)
        if wasAskingApp, engine.phase == .askingReason {
            engine.context = makeContext(appName: engine.subjectName)
        }
        return turn
    }

    /// Clears the conversation and starts over without a target.
    func reset() {
        start(target: nil)
    }

    /// Completes a pending FamilyControls grant with the apps picked in `appSelection`.
    func confirmAppSelection() {
        guard let minutes = pendingGrantMinutes else { needsAppSelection = false; return }
        let tokens = appSelection.applicationTokens
        guard !tokens.isEmpty else { return }
        pendingGrantMinutes = nil
        needsAppSelection = false
        let name = tokens.count == 1 ? (target?.displayName ?? "This app") : "\(tokens.count) apps"
        applyGrant(subjects: tokens.map { UnlockSubject.application($0) }, displayName: name, minutes: minutes)
    }

    func cancelAppSelection() {
        pendingGrantMinutes = nil
        needsAppSelection = false
        outcome = .declined
    }

    /// From the `.emergency` outcome / chip.
    func openEmergency() {
        env.presentSheet(.emergency)
    }

    // MARK: Turn presentation

    private func present(_ turn: ChatTurn, typing: Bool) {
        phase = engine.phase
        // A cooldown only lives while the engine is cooling down (e.g. the
        // user tapped "skip it" mid-countdown → cancel the timer).
        if case .coolingDown = engine.phase {} else {
            cooldownTask?.cancel()
            cooldownTask = nil
            cooldown = nil
        }
        // Never present an empty turn: it would wipe the chips and disable the
        // input, stranding the conversation.
        guard !turn.isEmpty else { return }
        quickReplies = []
        acceptsFreeText = false
        turnTask?.cancel()
        turnTask = Task { [weak self] in
            guard let self else { return }
            if typing, !turn.lines.isEmpty, self.typingDelay > .zero {
                self.isBobblyTyping = true
                try? await Task.sleep(for: self.typingDelay)
                self.isBobblyTyping = false
            }
            guard !Task.isCancelled else { return }
            for line in turn.lines {
                self.messages.append(ChatMessage(sender: .bobbly, text: line.text, style: line.style))
            }
            self.quickReplies = turn.quickReplies
            self.acceptsFreeText = turn.acceptsFreeText
            self.inputPlaceholder = turn.inputPlaceholder
            if turn.commitmentPhrase != nil { self.commitmentPhrase = turn.commitmentPhrase }
            if let cooldown = turn.cooldown { self.startCooldown(cooldown) }
            if let decision = turn.decision { self.apply(decision) }
        }
    }

    private func startCooldown(_ value: ChatCooldown) {
        cooldown = value
        cooldownTask?.cancel()
        cooldownTask = Task { [weak self] in
            let wait = max(0, value.endsAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            // The conversation may have moved on (gave up, restarted).
            guard case .coolingDown = self.engine.phase else {
                self.cooldown = nil
                return
            }
            self.cooldown = nil
            self.present(self.engine.respond(to: .cooldownElapsed, now: Date()), typing: false)
        }
    }

    // MARK: Decisions

    private func apply(_ decision: ChatDecision) {
        switch decision {
        case .grant(let minutes):
            if let subject = target?.subject, subject != .studySession {
                applyGrant(subjects: [subject], displayName: target?.displayName ?? engine.subjectName ?? "App", minutes: minutes)
            } else if env.engines.kind == .familyControls {
                // Token unknown (chat started from the tab): ask which app(s).
                // Starts empty so confirming never unlocks the whole block list.
                pendingGrantMinutes = minutes
                appSelection = FamilyActivitySelection()
                needsAppSelection = true
            } else {
                let name = engine.subjectName ?? "App"
                let canonical = env.makeTarget(appName: name, origin: .chatTab)
                if target == nil, let canonical { target = canonical }
                applyGrant(subjects: [.appName(canonical?.displayName ?? name)],
                           displayName: canonical?.displayName ?? name, minutes: minutes)
            }

        case .endStudy:
            env.study.endSessionEarly(reason: engine.reasonText)
            outcome = .studyEnded(name: target?.displayName ?? "Study")

        case .declined:
            env.companion.recordResistedTemptation()
            env.tracker.logUnlock(appName: target?.displayName ?? engine.subjectName ?? "App",
                                  appKey: target?.subject.appKey, reason: engine.reasonText,
                                  category: (engine.category ?? .unclear).rawValue, minutes: 0, granted: false)
            outcome = .declined

        case .emergency:
            outcome = .emergency
            openEmergency()
        }
        env.home.refresh()
    }

    /// One unlock for `subjects` (one counter increment, one UnlockEvent, one life check).
    private func applyGrant(subjects: [UnlockSubject], displayName: String, minutes: Int) {
        let unlocksBefore = env.shared.unlocksToday()
        let isEmergency = engine.category == .emergency
        do {
            let unlocks = try env.engines.grantUnlocks(subjects, displayName: displayName, minutes: minutes)
            var costLife = false
            if !isEmergency {
                costLife = env.companion.recordUnlock(unlocksBefore: unlocksBefore,
                                                      overDailyLimit: engine.context.isOverDailyLimit)
            }
            env.tracker.logUnlock(appName: displayName, appKey: subjects.first?.appKey, reason: engine.reasonText,
                                  category: (engine.category ?? .unclear).rawValue, minutes: minutes,
                                  granted: true, isEmergency: isEmergency, costLife: costLife)
            let until = unlocks.map(\.expiresAt).max() ?? Date().addingTimeInterval(TimeInterval(minutes * 60))
            outcome = .granted(appName: displayName, minutes: minutes, until: until,
                               costLife: costLife, reopenURL: target?.reopenURL)
        } catch {
            outcome = .failed(message: error.localizedDescription)
        }
    }

    // MARK: Helpers

    /// Strictness inputs. With an app name (Shortcuts engine), includes that
    /// app's usage today and daily limit so over-limit unlocks get stricter.
    private func makeContext(appName: String? = nil) -> ChatContext {
        var context = ChatContext(unlocksToday: env.shared.unlocksToday(),
                                  dailyFreeUnlocks: env.preferences.dailyFreeUnlocks,
                                  livesRemaining: env.companion.snapshot.lives)
        if let appName, env.engines.kind == .shortcuts {
            let key = AppKey.normalize(appName)
            if let limit = env.tracker.dailyLimits()[key] {
                let today = UsageAggregator.lastDays(1)
                let records = env.tracker.records(in: today).filter { $0.appKey == key }
                context.appUsageTodayMinutes = records.reduce(0) { $0 + UsageAggregator.overlap($1, with: today, now: Date()) } / 60
                context.appDailyLimitMinutes = limit
            }
        }
        return context
    }

    private func knownAppNames() -> [String] {
        env.engines.kind == .shortcuts ? env.tracker.knownAppNames() : []
    }

    private func cancelTasks() {
        turnTask?.cancel()
        cooldownTask?.cancel()
        isBobblyTyping = false
    }
}
