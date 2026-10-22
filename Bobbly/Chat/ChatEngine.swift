//  ChatEngine.swift
//  Bobbly/Chat — rule-based conversation that decides whether to unlock.
//
//  Flow:  greet → (ask app) → ask reason → classify
//    • work / school / message someone → grant 5–15 min (shorter each unlock today)
//    • emergency                       → grant 15 min (+ offer the free Emergency screen)
//    • boredom / habit                 → pushback + alternative → give up, OR
//                                        type a commitment sentence / wait 30–60 s → short grant
//    • unclear                         → ask once more, then treat as boredom
//  Ending a study session early uses the same flow; its "grant" is `.endStudy`.
//
//  Pure value type: deterministic given a seed, no I/O. ChatViewModel applies decisions.

import Foundation

// MARK: - Engine I/O types

/// Inputs that influence strictness.
struct ChatContext: Equatable, Sendable {
    /// Unlocks already granted today (before this conversation).
    var unlocksToday: Int
    /// Unlocks per day that don't cost a life.
    var dailyFreeUnlocks: Int
    var livesRemaining: Int
    /// Shortcuts engine: minutes the subject app was used today (if tracked).
    var appUsageTodayMinutes: Double? = nil
    /// Shortcuts engine: the subject app's daily limit (nil / 0 = none).
    var appDailyLimitMinutes: Int? = nil

    /// The app already used up its daily limit → shorter grant, costs a life.
    var isOverDailyLimit: Bool {
        guard let limit = appDailyLimitMinutes, limit > 0, let used = appUsageTodayMinutes else { return false }
        return used >= Double(limit)
    }

    static let relaxed = ChatContext(unlocksToday: 0, dailyFreeUnlocks: 3, livesRemaining: 3)
}

enum ChatPhase: Equatable, Sendable {
    case idle
    case askingApp
    case askingReason
    case pushback
    case awaitingCommitment
    case coolingDown(until: Date)
    case finished
}

enum ChatInput: Equatable {
    case text(String)
    case quickReply(QuickReply)
    /// Sent by the ViewModel when the cooldown timer reaches zero.
    case cooldownElapsed
}

enum ChatDecision: Equatable, Sendable {
    case grant(minutes: Int)
    case endStudy
    case declined
    case emergency
}

struct ChatLine: Equatable, Sendable {
    var text: String
    var style: ChatMessageStyle

    init(_ text: String, style: ChatMessageStyle = .normal) {
        self.text = text
        self.style = style
    }
}

/// One Bobbly response.
struct ChatTurn: Equatable {
    var lines: [ChatLine] = []
    var quickReplies: [QuickReply] = []
    var acceptsFreeText: Bool = true
    var inputPlaceholder: String = "Type a message…"
    var cooldown: ChatCooldown?
    var commitmentPhrase: String?
    var decision: ChatDecision?

    static let none = ChatTurn(acceptsFreeText: false)

    /// Nothing to show or do (the engine ignored the input). Presenting it
    /// would wipe the current chips/input, so the ViewModel skips it.
    var isEmpty: Bool {
        lines.isEmpty && quickReplies.isEmpty && decision == nil && cooldown == nil && commitmentPhrase == nil
    }
}

/// SplitMix64 — tiny deterministic RNG so tests can pin phrase choices.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Engine

struct ChatEngine {
    private(set) var phase: ChatPhase = .idle
    /// App name (or study session name) being discussed.
    private(set) var subjectName: String?
    private(set) var isStudySession = false
    private(set) var category: ReasonCategory?
    /// What the user said as their reason (logged to UnlockEvent).
    private(set) var reasonText = ""
    private(set) var commitmentPhrase: String?
    private(set) var clarifyAttempts = 0
    private(set) var knownApps: [String] = []
    var context: ChatContext

    private var rng: SeededRandom

    init(context: ChatContext, seed: UInt64 = UInt64(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))) {
        self.context = context
        self.rng = SeededRandom(seed: seed)
    }

    // MARK: Strictness rules

    static let emergencyMinutes = 15

    /// Legitimate: 15 → 10 → 5. After boredom effort: 7 → 5 → 3. Emergency: 15.
    static func grantMinutes(for category: ReasonCategory, unlocksToday: Int) -> Int {
        let n = max(0, unlocksToday)
        switch category {
        case .emergency: return emergencyMinutes
        case .work, .school, .communication: return max(5, 15 - 5 * n)
        case .boredom, .habit, .unclear: return max(3, 7 - 2 * n)
        }
    }

    /// 30 s, +10 s per unlock today, max 60 s.
    static func cooldownSeconds(unlocksToday: Int) -> Int {
        min(60, 30 + 10 * max(0, unlocksToday))
    }

    // MARK: Conversation

    /// Starts (or restarts) a conversation.
    /// - Parameters:
    ///   - subjectName: app name / study session name; `nil` asks which app.
    ///   - knownApps: names offered as chips when asking which app.
    mutating func start(subjectName: String?, isStudySession: Bool = false, knownApps: [String] = []) -> ChatTurn {
        self.subjectName = subjectName
        self.isStudySession = isStudySession
        self.knownApps = knownApps
        category = nil
        reasonText = ""
        commitmentPhrase = nil
        clarifyAttempts = 0

        var turn = ChatTurn()
        turn.lines.append(ChatLine(pick(ChatPhrases.greetings)))
        if subjectName == nil {
            phase = .askingApp
            turn.lines.append(ChatLine(pick(ChatPhrases.askApp)))
            turn.quickReplies = knownApps.prefix(6).map { QuickReply($0, kind: .app($0)) }
            turn.inputPlaceholder = "App name…"
        } else {
            phase = .askingReason
            turn.lines.append(ChatLine(fill(pick(isStudySession ? ChatPhrases.askStudyReason : ChatPhrases.askReason))))
            turn.quickReplies = Self.reasonReplies
            turn.inputPlaceholder = "Tell Bobbly why…"
        }
        return turn
    }

    mutating func respond(to input: ChatInput, now: Date = Date()) -> ChatTurn {
        if case .quickReply(let reply) = input, reply.kind == .startOver {
            return start(subjectName: isStudySession ? subjectName : nil, isStudySession: isStudySession, knownApps: knownApps)
        }

        switch phase {
        case .idle:
            return .none

        case .finished:
            if case .quickReply(let reply) = input, reply.kind == .openEmergency {
                return ChatTurn(acceptsFreeText: false, decision: .emergency)
            }
            return .none

        case .askingApp:
            let name: String?
            switch input {
            case .text(let text): name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .quickReply(let reply):
                if case .app(let app) = reply.kind { name = app } else { name = nil }
            case .cooldownElapsed: name = nil
            }
            guard let name, !name.isEmpty else { return .none }
            subjectName = name
            phase = .askingReason
            var turn = ChatTurn()
            turn.lines = [ChatLine(fill(pick(ChatPhrases.askReason)))]
            turn.quickReplies = Self.reasonReplies
            turn.inputPlaceholder = "Tell Bobbly why…"
            return turn

        case .askingReason:
            switch input {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return .none }
                reasonText = reasonText.isEmpty ? trimmed : reasonText + " / " + trimmed
                return evaluate(Self.classify(trimmed), now: now)
            case .quickReply(let reply):
                guard case .reason(let picked) = reply.kind else { return .none }
                reasonText = picked.title
                return evaluate(picked, now: now)
            case .cooldownElapsed:
                return .none
            }

        case .pushback:
            switch input {
            case .quickReply(let reply):
                switch reply.kind {
                case .giveUp: return decline()
                case .unlockAnyway: return beginCommitment()
                case .waitCooldown: return beginCooldown(now: now)
                default: return .none
                }
            case .text(let text):
                let reclassified = Self.classify(text)
                if reclassified.isLegitimate || reclassified == .emergency {
                    reasonText += " / " + text
                    return evaluate(reclassified, now: now)
                }
                return beginCommitment()
            case .cooldownElapsed:
                return .none
            }

        case .awaitingCommitment:
            switch input {
            case .text(let text):
                if let phrase = commitmentPhrase, Self.matchesCommitment(text, phrase: phrase) {
                    return grantAfterEffort()
                }
                var turn = ChatTurn()
                turn.lines = [ChatLine(pick(ChatPhrases.commitmentMismatch))]
                turn.quickReplies = effortReplies
                turn.commitmentPhrase = commitmentPhrase
                turn.inputPlaceholder = "Type the sentence…"
                return turn
            case .quickReply(let reply):
                switch reply.kind {
                case .waitCooldown: return beginCooldown(now: now)
                case .giveUp: return decline()
                default: return .none
                }
            case .cooldownElapsed:
                return .none
            }

        case .coolingDown(let until):
            if case .quickReply(let reply) = input, reply.kind == .giveUp {
                return decline()
            }
            if now >= until {
                return grantAfterEffort()
            }
            var turn = ChatTurn(acceptsFreeText: false)
            let remaining = max(1, Int(until.timeIntervalSince(now).rounded(.up)))
            turn.lines = [ChatLine(fill(pick(ChatPhrases.cooldownNotDone), sec: remaining))]
            turn.quickReplies = [QuickReply("You're right, I'll skip it", kind: .giveUp)]
            turn.cooldown = ChatCooldown(startedAt: now, endsAt: until)
            return turn
        }
    }

    // MARK: Steps

    private mutating func evaluate(_ category: ReasonCategory, now: Date) -> ChatTurn {
        self.category = category
        switch category {
        case .work, .school, .communication:
            return grant(minutes: Self.grantMinutes(for: category, unlocksToday: context.unlocksToday),
                         bank: isStudySession ? ChatPhrases.approveStudyEnd : ChatPhrases.approve)
        case .emergency:
            var turn = grant(minutes: Self.emergencyMinutes,
                             bank: isStudySession ? ChatPhrases.approveStudyEnd : ChatPhrases.emergency)
            turn.quickReplies = [QuickReply("Open Emergency unblock", kind: .openEmergency)]
            return turn
        case .unclear where clarifyAttempts == 0:
            clarifyAttempts += 1
            var turn = ChatTurn()
            turn.lines = [ChatLine(pick(ChatPhrases.clarify))]
            turn.quickReplies = Self.reasonReplies
            turn.inputPlaceholder = "Tell Bobbly why…"
            return turn
        case .boredom, .habit, .unclear:
            phase = .pushback
            var turn = ChatTurn()
            turn.lines = [ChatLine(fill(pick(ChatPhrases.pushback)))]
            turn.quickReplies = [
                QuickReply("You're right, I'll skip it", kind: .giveUp),
                QuickReply("I still want in", kind: .unlockAnyway),
            ]
            return turn
        }
    }

    private mutating func beginCommitment() -> ChatTurn {
        phase = .awaitingCommitment
        let phrase = fill(pick(ChatPhrases.commitmentSentences))
        commitmentPhrase = phrase
        var turn = ChatTurn()
        turn.lines = [ChatLine(pick(ChatPhrases.commitmentIntro)), ChatLine(phrase, style: .commitment)]
        turn.quickReplies = effortReplies
        turn.commitmentPhrase = phrase
        turn.inputPlaceholder = "Type the sentence…"
        return turn
    }

    private mutating func beginCooldown(now: Date) -> ChatTurn {
        let seconds = Self.cooldownSeconds(unlocksToday: context.unlocksToday)
        let until = now.addingTimeInterval(TimeInterval(seconds))
        phase = .coolingDown(until: until)
        var turn = ChatTurn(acceptsFreeText: false)
        turn.lines = [ChatLine(fill(pick(ChatPhrases.cooldownStart), sec: seconds))]
        turn.quickReplies = [QuickReply("You're right, I'll skip it", kind: .giveUp)]
        turn.cooldown = ChatCooldown(startedAt: now, endsAt: until)
        return turn
    }

    private mutating func grantAfterEffort() -> ChatTurn {
        let effortCategory = category ?? .boredom
        return grant(minutes: Self.grantMinutes(for: effortCategory, unlocksToday: context.unlocksToday),
                     bank: isStudySession ? ChatPhrases.approveStudyEnd : ChatPhrases.grantedAfterEffort)
    }

    private mutating func grant(minutes: Int, bank: [String]) -> ChatTurn {
        phase = .finished
        var turn = ChatTurn(acceptsFreeText: false)
        if isStudySession {
            turn.lines = [ChatLine(pick(bank), style: .decision)]
            turn.decision = .endStudy
            return turn
        }
        let isEmergency = category == .emergency
        var minutes = minutes
        if context.unlocksToday >= 1 {
            turn.lines.append(ChatLine(pick(ChatPhrases.strictness).replacingOccurrences(of: "{n}", with: "\(context.unlocksToday + 1)")))
        }
        if context.isOverDailyLimit && !isEmergency {
            minutes = Self.overLimitMinutes(minutes)
            let used = Int((context.appUsageTodayMinutes ?? 0).rounded())
            let limit = context.appDailyLimitMinutes ?? 0
            let line = fill(pick(ChatPhrases.overLimit))
                .replacingOccurrences(of: "{used}", with: "\(used)")
                .replacingOccurrences(of: "{limit}", with: "\(limit)")
            turn.lines.append(ChatLine(line, style: .warning))
        }
        if context.livesRemaining <= 0 {
            turn.lines.append(ChatLine(pick(ChatPhrases.outOfLives), style: .warning))
        } else if !isEmergency && (context.unlocksToday >= context.dailyFreeUnlocks || context.isOverDailyLimit) {
            turn.lines.append(ChatLine(pick(ChatPhrases.lifeWarning), style: .warning))
        }
        turn.lines.append(ChatLine(fill(pick(bank), minutes: minutes), style: .decision))
        turn.decision = .grant(minutes: minutes)
        return turn
    }

    /// Grants for an app already past its daily limit are halved (min 3 min).
    static func overLimitMinutes(_ minutes: Int) -> Int {
        max(3, minutes / 2)
    }

    private mutating func decline() -> ChatTurn {
        phase = .finished
        var turn = ChatTurn(acceptsFreeText: false)
        turn.lines = [ChatLine(pick(ChatPhrases.declined), style: .decision)]
        turn.quickReplies = [QuickReply("Start over", kind: .startOver)]
        turn.decision = .declined
        return turn
    }

    private var effortReplies: [QuickReply] {
        [
            QuickReply("Wait \(Self.cooldownSeconds(unlocksToday: context.unlocksToday))s instead", kind: .waitCooldown),
            QuickReply("You're right, I'll skip it", kind: .giveUp),
        ]
    }

    static let reasonReplies: [QuickReply] = [
        ReasonCategory.work, .school, .communication, .boredom, .habit, .emergency,
    ].map { QuickReply($0.title, kind: .reason($0)) }

    // MARK: Text helpers

    private mutating func pick(_ bank: [String]) -> String {
        bank.randomElement(using: &rng) ?? ""
    }

    private mutating func fill(_ template: String, minutes: Int? = nil, sec: Int? = nil) -> String {
        var text = template.replacingOccurrences(of: "{app}", with: subjectName ?? "that app")
        if let minutes { text = text.replacingOccurrences(of: "{min}", with: "\(minutes)") }
        if let sec { text = text.replacingOccurrences(of: "{sec}", with: "\(sec)") }
        if text.contains("{alt}") {
            text = text.replacingOccurrences(of: "{alt}", with: pick(ChatPhrases.alternatives))
        }
        return text
    }

    // MARK: Classification

    private struct Keyword {
        let term: String
        let category: ReasonCategory
        let weight: Int
    }

    private static func keywords(_ category: ReasonCategory, _ weight: Int, _ terms: [String]) -> [Keyword] {
        terms.map { Keyword(term: $0, category: category, weight: weight) }
    }

    /// `*` suffix = prefix match on a word; multi-word terms match as phrases.
    private static let keywordTable: [Keyword] =
        keywords(.emergency, 3, ["emergency", "urgent", "911", "hospital", "ambulance", "police", "danger",
                                 "hurt", "injured", "accident", "asap", "help me", "fire"])
        + keywords(.boredom, 2, ["bored", "boring", "nothing to do", "kill time", "killing time", "entertain*",
                                 "procrastinat*", "fun", "relax", "chill", "waste time", "wasting time"])
        + keywords(.habit, 2, ["habit", "just because", "idk", "i dont know", "dunno", "muscle memory",
                               "automatically", "scroll*", "doomscroll*", "no reason", "whatever", "feed"])
        + keywords(.school, 1, ["school", "homework", "class", "classes", "teacher", "assignment*", "study*",
                                "exam*", "test", "quiz*", "lecture*", "professor", "essay", "research",
                                "project", "college", "university", "uni", "course*", "grade*"])
        + keywords(.work, 1, ["work*", "job", "boss", "client*", "meeting*", "email*", "slack", "deadline*",
                              "shift", "office", "colleague*", "coworker*", "business", "manager", "customer*"])
        + keywords(.communication, 1, ["message*", "msg", "text*", "reply", "respond*", "dm", "dms", "call*",
                                       "mom", "mum", "dad", "parent*", "friend*", "family", "sister", "brother",
                                       "girlfriend", "boyfriend", "wife", "husband", "partner", "chat*",
                                       "answer*", "contact*", "group chat", "talk to"])

    /// Tie-break order: legitimate reasons win ties over boredom/habit.
    private static let priority: [ReasonCategory] = [.emergency, .school, .work, .communication, .boredom, .habit]

    /// Keyword classifier with weights (explicit boredom admissions outweigh one legit word).
    static func classify(_ text: String) -> ReasonCategory {
        let normalized = normalizeForComparison(text)
        guard !normalized.isEmpty else { return .unclear }
        let words = normalized.split(separator: " ").map(String.init)
        let padded = " \(normalized) "

        var scores: [ReasonCategory: Int] = [:]
        for keyword in keywordTable {
            let matched: Bool
            if keyword.term.contains(" ") {
                matched = padded.contains(" \(keyword.term) ")
            } else if keyword.term.hasSuffix("*") {
                let stem = String(keyword.term.dropLast())
                matched = words.contains { $0.hasPrefix(stem) }
            } else {
                matched = words.contains(keyword.term)
            }
            if matched { scores[keyword.category, default: 0] += keyword.weight }
        }

        guard let best = scores.values.max(), best > 0 else { return .unclear }
        return priority.first { scores[$0] == best } ?? .unclear
    }

    /// Lowercased, apostrophes removed, punctuation → spaces, single spaces.
    static func normalizeForComparison(_ text: String) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let mapped = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func matchesCommitment(_ typed: String, phrase: String) -> Bool {
        let a = normalizeForComparison(typed)
        return !a.isEmpty && a == normalizeForComparison(phrase)
    }
}
