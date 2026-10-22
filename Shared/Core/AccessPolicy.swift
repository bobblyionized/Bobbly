//  AccessPolicy.swift
//  Shared/Core — pure access decision used by the Shortcuts engine and
//  `CheckAccessIntent`. No I/O: feed it a snapshot, get a decision.

import Foundation

/// Everything the access decision depends on.
struct AccessSnapshot: Equatable, Sendable {
    var isDetached: Bool
    var emergencyUntil: Date?
    /// Normalized names (see `AppKey.normalize`).
    var blockedAppKeys: Set<String>
    var grants: [UnlockGrant]
    var study: ActiveStudy?
    /// Quick setup: whether the group ("one of your blocked apps") is blocked
    /// at all. Settings › "Quick setup blocking" turns it off.
    var groupBlockingEnabled: Bool = true

    static let empty = AccessSnapshot(isDetached: false, emergencyUntil: nil, blockedAppKeys: [], grants: [], study: nil)
}

enum AccessDecision: Equatable, Sendable {
    enum AllowReason: Equatable, Sendable {
        /// Bobbly is detached ("Bobbly off").
        case detached
        /// Emergency unblock is running until the date.
        case emergency(until: Date)
        /// A chat-granted unlock is running until the date.
        case unlocked(until: Date)
        /// Allowed by the active study whitelist.
        case whitelisted
        /// The app is not blocked at all.
        case notBlocked
    }

    enum BlockReason: Equatable, Sendable {
        /// The app is on the block list.
        case blockedApp
        /// A study session is running and the app is not on its whitelist.
        case studySession(whitelistName: String)
    }

    case allowed(AllowReason)
    case blocked(BlockReason)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

enum AccessPolicy {
    /// Decides whether `appName` may be opened right now.
    ///
    /// Order of precedence: detach > emergency > active unlock > study session
    /// (whitelist wins, everything else blocked) > block list > allowed.
    static func decide(appName: String, snapshot: AccessSnapshot, now: Date) -> AccessDecision {
        let key = AppKey.normalize(appName)
        if key == AppKey.group { return decideGroup(snapshot: snapshot, now: now) }

        if snapshot.isDetached { return .allowed(.detached) }

        if let until = snapshot.emergencyUntil, until > now {
            return .allowed(.emergency(until: until))
        }

        if let grant = snapshot.grants
            .filter({ $0.appKey == key && $0.isActive(at: now) })
            .max(by: { $0.expiresAt < $1.expiresAt }) {
            return .allowed(.unlocked(until: grant.expiresAt))
        }

        if let study = snapshot.study, study.isActive(at: now) {
            if study.allowedAppKeys.map(AppKey.normalize).contains(key) {
                return .allowed(.whitelisted)
            }
            return .blocked(.studySession(whitelistName: study.whitelistName))
        }

        if snapshot.blockedAppKeys.contains(key) {
            return .blocked(.blockedApp)
        }

        return .allowed(.notBlocked)
    }

    /// GROUP mode (quick setup, `AppKey.group`): the automation only fires for
    /// apps the user marked as distracting, so they are blocked as one unit.
    ///
    /// Order: detach > emergency > active group unlock > study session (group
    /// apps are distracting by definition, never whitelisted) > quick-setup
    /// blocking toggle.
    static func decideGroup(snapshot: AccessSnapshot, now: Date) -> AccessDecision {
        if snapshot.isDetached { return .allowed(.detached) }
        if let until = snapshot.emergencyUntil, until > now {
            return .allowed(.emergency(until: until))
        }
        if let grant = snapshot.grants
            .filter({ $0.appKey == AppKey.group && $0.isActive(at: now) })
            .max(by: { $0.expiresAt < $1.expiresAt }) {
            return .allowed(.unlocked(until: grant.expiresAt))
        }
        if let study = snapshot.study, study.isActive(at: now) {
            return .blocked(.studySession(whitelistName: study.whitelistName))
        }
        return snapshot.groupBlockingEnabled ? .blocked(.blockedApp) : .allowed(.notBlocked)
    }
}
