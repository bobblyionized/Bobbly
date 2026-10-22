//  SharedModels.swift
//  Shared/Core — value types persisted in the App Group store.

import Foundation
import FamilyControls
import ManagedSettings

/// Which blocking engine is running.
enum EngineKind: String, Codable, CaseIterable, Sendable {
    /// Real blocking through FamilyControls / ManagedSettings shields (primary).
    case familyControls
    /// Soft blocking through Shortcuts personal automations + App Intents (fallback).
    case shortcuts

    var displayName: String {
        switch self {
        case .familyControls: return "Screen Time (FamilyControls)"
        case .shortcuts: return "Shortcuts automations"
        }
    }
}

/// Normalizes app names typed by users / passed by Shortcuts so that
/// "Instagram", " instagram " and "INSTAGRAM" all match.
enum AppKey {
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    // MARK: Quick-setup group ("one of your blocked apps")

    /// Reserved key for GROUP mode: a single "When <several apps> Is Opened"
    /// automation can't tell Bobbly which app opened, so all of them share
    /// one access decision and one unlock grant under this key.
    static let group = "__bobbly_group__"

    /// The bucket name group-mode usage/interruptions are logged under
    /// (shows as one "Blocked apps" entry in Stats and Search).
    static let groupDisplayName = "Blocked apps"

    /// How Bobbly refers to the unknown app in group-mode copy ("Why do you
    /// want to open this app?").
    static let groupSubjectName = "this app"

    static func isGroup(_ name: String?) -> Bool {
        guard let name else { return false }
        return normalize(name) == group
    }
}

/// JSON coding helpers for opaque FamilyControls tokens and selections.
enum TokenCoding {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// A temporary unlock for one app. Shortcuts grants are keyed by `appKey`;
/// FamilyControls grants carry an encoded `ApplicationToken`.
struct UnlockGrant: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// Normalized app name (Shortcuts engine). `nil` for token-only grants.
    var appKey: String?
    /// JSON-encoded `ApplicationToken` (FamilyControls engine).
    var tokenData: Data?
    /// Human readable name if known ("Instagram"); token grants may only know "This app".
    var displayName: String
    var grantedAt: Date
    var expiresAt: Date

    init(id: UUID = UUID(), appKey: String?, tokenData: Data?, displayName: String, grantedAt: Date, expiresAt: Date) {
        self.id = id
        self.appKey = appKey
        self.tokenData = tokenData
        self.displayName = displayName
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }

    func isActive(at now: Date) -> Bool { expiresAt > now }

    var applicationToken: ApplicationToken? {
        TokenCoding.decode(ApplicationToken.self, from: tokenData)
    }
}

/// The currently running study session as seen by extensions and intents.
struct ActiveStudy: Codable, Hashable, Sendable {
    /// `StudySession.id` in SwiftData.
    var sessionID: UUID
    var whitelistID: UUID
    var whitelistName: String
    /// JSON-encoded `FamilyActivitySelection` of the allowed apps (FamilyControls engine).
    var selectionData: Data?
    /// Normalized names of tracked apps that stay allowed (Shortcuts engine).
    var allowedAppKeys: [String]
    var startedAt: Date
    /// `nil` = runs until the user stops it.
    var endsAt: Date?

    func isActive(at now: Date) -> Bool {
        guard let endsAt else { return true }
        return endsAt > now
    }

    var selection: FamilyActivitySelection {
        TokenCoding.decode(FamilyActivitySelection.self, from: selectionData) ?? FamilyActivitySelection()
    }
}

/// How a study session ended, recorded by whoever ended it.
struct StudyEndRecord: Codable, Hashable, Sendable {
    enum Reason: String, Codable, Sendable {
        /// The timer ran out (completed → bonus).
        case completed
        /// Ended early through the chat.
        case endedEarly
        /// Emergency detach / Screen Time revoked (no bonus, no penalty).
        case detached
    }

    var sessionID: UUID
    var endedAt: Date
    var reason: Reason
}

/// Written by `BobblyGateIntent` when it decides to bring up the Gate; the app
/// consumes it when it reaches the foreground (or via the in-process
/// `.bobblyGateRequested` notification). Stale after `PendingGateRequest.lifetime`.
struct PendingGateRequest: Codable, Hashable, Sendable {
    /// `nil` = group mode (unknown app).
    var appName: String?
    var requestedAt: Date

    static let lifetime: TimeInterval = 120

    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(requestedAt)
        return age >= -5 && age < Self.lifetime
    }
}

/// "Test it" evidence for the quick-setup automations.
struct QuickSetupRunStats: Codable, Hashable, Sendable {
    var gateRuns: Int = 0
    var lastGateRunAt: Date?
    var closedRuns: Int = 0
    var lastClosedRunAt: Date?
}

/// Display name of a shielded app, keyed by its encoded token.
struct ShieldedAppName: Codable, Hashable, Sendable {
    var applicationTokenData: Data
    var name: String
    var recordedAt: Date
}

/// Written by the shield-action extension when the user taps "Talk to Bobbly"
/// on a shield. The app consumes it when the notification is opened.
struct PendingShieldRequest: Codable, Hashable, Sendable {
    /// JSON-encoded `ApplicationToken` of the shielded app, if it was an app.
    var applicationTokenData: Data?
    /// JSON-encoded `WebDomainToken`, if it was a website.
    var webDomainTokenData: Data?
    /// Display name if the shield-configuration extension recorded it.
    var appName: String?
    var requestedAt: Date

    var applicationToken: ApplicationToken? {
        TokenCoding.decode(ApplicationToken.self, from: applicationTokenData)
    }
}
