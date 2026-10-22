//  ShieldContent.swift
//  BobblyShieldConfig — WHAT the shield says (Core-owned logic).
//  HOW it looks is in ShieldStyle.swift (UI-owned).

import Foundation
import ManagedSettings

/// Bobbly's mood as the shield sees it (mirrors the app's CompanionMood tiers).
enum ShieldMood: String {
    case thriving, happy, okay, sad, exhausted

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

/// Everything ShieldStyle needs to build a `ShieldConfiguration`.
struct ShieldContent {
    enum Kind {
        /// On the user's block list.
        case blockedApp
        /// Shielded because a study session is running.
        case studySession(name: String)
        /// A blocked website.
        case website
    }

    var kind: Kind
    /// "Instagram" (nil if iOS didn't provide a name).
    var appName: String?
    var title: String
    var subtitle: String
    /// "Talk to Bobbly", or "Tap the notification ↑" right after it was pressed.
    var primaryButton: String
    /// "Go back"
    var secondaryButton: String?
    var mood: ShieldMood
    var lives: Int
    var unlocksToday: Int
    var freeUnlocksLeft: Int
    /// `true` for ~2 minutes after "Talk to Bobbly" was pressed.
    var notificationRecentlySent: Bool
}

enum ShieldContentBuilder {
    static func make(appName: String?, isStudy: Bool, isWebsite: Bool,
                     shared: SharedStore = .shared, now: Date = Date()) -> ShieldContent {
        let lives = shared.companionLives
        let mood = ShieldMood(mood: shared.companionMood, lives: lives)
        let unlocks = shared.unlocksToday(now: now)
        let freeLeft = max(0, shared.dailyFreeUnlocks - unlocks)
        let recentlySent = (shared.lastShieldNotificationAt.map { now.timeIntervalSince($0) < 120 }) ?? false
        let name = appName ?? (isWebsite ? "This website" : "This app")

        let kind: ShieldContent.Kind
        let title: String
        var subtitle: String
        if let study = shared.activeStudy, isStudy, study.isActive(at: now) {
            kind = .studySession(name: study.whitelistName)
            title = "Study time!"
            subtitle = "\(name) isn't on your \(study.whitelistName) whitelist."
        } else if isWebsite {
            kind = .website
            title = "\(name) is blocked"
            subtitle = "Bobbly is keeping you focused."
        } else {
            kind = .blockedApp
            title = "\(name) is blocked"
            subtitle = freeLeft > 0
                ? "Talk to Bobbly to unlock it. \(freeLeft) free unlock\(freeLeft == 1 ? "" : "s") left today."
                : "Talk to Bobbly to unlock it. More unlocks today cost Bobbly a life."
        }
        if recentlySent {
            subtitle = "Bobbly sent you a notification. Tap it to start chatting."
        }

        return ShieldContent(kind: kind, appName: appName, title: title, subtitle: subtitle,
                             primaryButton: recentlySent ? "Tap the notification ↑" : "Talk to Bobbly",
                             secondaryButton: "Go back", mood: mood, lives: lives,
                             unlocksToday: unlocks, freeUnlocksLeft: freeLeft,
                             notificationRecentlySent: recentlySent)
    }
}
