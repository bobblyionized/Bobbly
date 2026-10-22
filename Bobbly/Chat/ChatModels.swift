//  ChatModels.swift
//  Bobbly/Chat — UI-facing chat types (rendered by ChatView).

import Foundation
import ManagedSettings

/// Who wrote a bubble.
enum ChatSender: String, Hashable, Sendable {
    case bobbly
    case user
    /// Centered system notice ("Instagram unlocked for 10 min").
    case system
}

/// Visual emphasis for a bubble.
enum ChatMessageStyle: String, Hashable, Sendable {
    case normal
    /// A grant / decline / study-end outcome.
    case decision
    /// Warnings ("This unlock will cost Bobbly a life").
    case warning
    /// The sentence the user must type to unlock anyway.
    case commitment
}

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let sender: ChatSender
    let text: String
    let style: ChatMessageStyle
    let timestamp: Date

    init(id: UUID = UUID(), sender: ChatSender, text: String, style: ChatMessageStyle = .normal, timestamp: Date = Date()) {
        self.id = id
        self.sender = sender
        self.text = text
        self.style = style
        self.timestamp = timestamp
    }
}

/// Why the user wants in. Keyword-classified from free text or picked from chips.
enum ReasonCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case work
    case school
    case communication
    case emergency
    case boredom
    case habit
    case unclear

    /// Legitimate reasons get 5–15 minutes without pushback.
    var isLegitimate: Bool { self == .work || self == .school || self == .communication }

    /// Chip title.
    var title: String {
        switch self {
        case .work: return "Work"
        case .school: return "School"
        case .communication: return "Message someone"
        case .emergency: return "Emergency"
        case .boredom: return "I'm bored"
        case .habit: return "Just habit"
        case .unclear: return "Something else"
        }
    }
}

/// A tappable suggestion chip under the last Bobbly message.
struct QuickReply: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Pick the app to unlock (chat started without a target).
        case app(String)
        /// Pick a reason category.
        case reason(ReasonCategory)
        /// "I still want in" after pushback.
        case unlockAnyway
        /// "You're right, I'll skip it."
        case giveUp
        /// Choose the cooldown instead of typing the commitment.
        case waitCooldown
        /// Jump to the Emergency screen.
        case openEmergency
        /// Start a new conversation.
        case startOver
    }

    let id: String
    let title: String
    let kind: Kind

    init(_ title: String, kind: Kind) {
        self.title = title
        self.kind = kind
        self.id = "\(kind)|\(title)"
    }
}

/// Where a conversation was started from.
enum ChatOrigin: String, Hashable, Sendable {
    /// User opened the Chat tab.
    case chatTab
    /// Gate screen (Shortcuts `bobbly://gate`).
    case gate
    /// Tapped the shield's "Talk to Bobbly" notification.
    case shield
    /// "End study session early".
    case studyEnd
}

/// What the conversation is about.
struct ChatTarget: Identifiable, Hashable {
    let id: UUID
    var subject: UnlockSubject
    /// "Instagram"; for `.application` tokens the app may not know the name —
    /// UI should render `Label(token)` instead (see CONTRACT.md).
    var displayName: String
    var origin: ChatOrigin
    /// Shortcuts engine: URL that re-opens the app after a grant.
    var reopenURL: URL?

    init(id: UUID = UUID(), subject: UnlockSubject, displayName: String, origin: ChatOrigin, reopenURL: URL? = nil) {
        self.id = id
        self.subject = subject
        self.displayName = displayName
        self.origin = origin
        self.reopenURL = reopenURL
    }

    static func studySession(named name: String) -> ChatTarget {
        ChatTarget(subject: .studySession, displayName: name, origin: .studyEnd)
    }

    /// Quick-setup GROUP target: "one of your blocked apps" (the automation
    /// can't say which). Unlocks apply to the whole group; the app can't be
    /// reopened by URL (`reopenURL == nil`) — the user swipes back to it.
    static func blockedAppsGroup(origin: ChatOrigin) -> ChatTarget {
        ChatTarget(subject: .appName(AppKey.group), displayName: AppKey.groupSubjectName, origin: origin, reopenURL: nil)
    }

    /// `true` for the quick-setup group target.
    var isBlockedAppsGroup: Bool { subject.isBlockedAppsGroup }

    /// Name usage / interruptions / unlocks are logged and shown under
    /// ("Blocked apps" for the group, else `displayName`).
    var trackingName: String { isBlockedAppsGroup ? AppKey.groupDisplayName : displayName }
}

extension UnlockSubject {
    /// The quick-setup group ("one of your blocked apps").
    static var blockedAppsGroup: UnlockSubject { .appName(AppKey.group) }

    var isBlockedAppsGroup: Bool {
        if case .appName(let name) = self { return AppKey.isGroup(name) }
        return false
    }
}

/// Final result of a conversation, shown as a banner/card by ChatView.
enum ChatOutcome: Equatable {
    /// Unlock granted until `until`. `reopenURL` lets the UI offer "Open <app>".
    case granted(appName: String, minutes: Int, until: Date, costLife: Bool, reopenURL: URL?)
    /// Study session ended early.
    case studyEnded(name: String)
    /// The user backed out. Bobbly is happy.
    case declined
    /// The user chose the emergency route (router opens Emergency).
    case emergency
    /// Something failed (e.g. engine error) — message is user-facing.
    case failed(message: String)
}

/// How the user gets back to the unlocked app (result card / Gate).
enum PostUnlockAction: Equatable {
    /// Known app with a URL scheme: offer "Open <app>" → `openURL(url)`.
    case reopen(appName: String, url: URL)
    /// Unknown app (quick-setup group) or no scheme: "Unlocked for N min —
    /// swipe back to your app" (home-indicator swipe / app switcher).
    case swipeBack(minutes: Int, until: Date)

    /// Derives the action from a chat outcome; `nil` unless it's a grant.
    init?(outcome: ChatOutcome?) {
        guard case .granted(let appName, let minutes, let until, _, let url)? = outcome else { return nil }
        if let url {
            self = .reopen(appName: appName, url: url)
        } else {
            self = .swipeBack(minutes: minutes, until: until)
        }
    }

    /// Ready-made copy, e.g. "Unlocked for 10 min — swipe back to your app".
    var message: String {
        switch self {
        case .reopen(let appName, _): return "Open \(appName)"
        case .swipeBack(let minutes, _): return "Unlocked for \(minutes) min — swipe back to your app"
        }
    }
}

/// Running cooldown ("wait 45 s to unlock anyway").
struct ChatCooldown: Equatable {
    let startedAt: Date
    let endsAt: Date
    var totalSeconds: Int { Int(endsAt.timeIntervalSince(startedAt).rounded()) }

    func remainingSeconds(at now: Date = Date()) -> Int { max(0, Int(endsAt.timeIntervalSince(now).rounded(.up))) }
    func progress(at now: Date = Date()) -> Double {
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(startedAt) / total))
    }
}
