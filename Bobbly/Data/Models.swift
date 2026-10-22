//  Models.swift
//  Bobbly/Data — SwiftData models (app process only; extensions use SharedStore).
//
//  Enum-like fields are stored as raw Strings (`…Raw`) with typed computed
//  accessors, because SwiftData predicates on custom enums are unreliable on iOS 17.

import Foundation
import SwiftData
import FamilyControls

// MARK: - TrackedApp

/// An app the user tracks/blocks. Used by the Shortcuts engine (by name + URL
/// scheme) and for tracker search suggestions in both engines.
@Model
final class TrackedApp {
    @Attribute(.unique) var id: UUID
    var name: String
    /// `AppKey.normalize(name)`; what Shortcuts passes to the intents.
    var appKey: String
    /// e.g. "instagram" (without "://"). Used to re-open the app after an unlock.
    var urlScheme: String?
    /// 0 = no limit.
    var dailyLimitMinutes: Int
    var isBlocked: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, urlScheme: String? = nil, dailyLimitMinutes: Int = 0, isBlocked: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.appKey = AppKey.normalize(name)
        self.urlScheme = urlScheme
        self.dailyLimitMinutes = dailyLimitMinutes
        self.isBlocked = isBlocked
        self.createdAt = createdAt
    }

    /// `instagram://` style URL, if a scheme is known.
    var openURL: URL? {
        guard let urlScheme, !urlScheme.isEmpty else { return nil }
        return URL(string: urlScheme.contains("://") ? urlScheme : "\(urlScheme)://")
    }
}

// MARK: - Whitelist

/// A named set of apps allowed during a study session.
@Model
final class Whitelist {
    @Attribute(.unique) var id: UUID
    var name: String
    /// JSON-encoded `FamilyActivitySelection` (FamilyControls engine).
    var selectionData: Data?
    /// Normalized names of tracked apps allowed (Shortcuts engine).
    var allowedAppKeys: [String]
    var createdAt: Date
    var updatedAt: Date
    /// Screen Time access was revoked after the apps were picked: the saved
    /// tokens were cleared and the user must pick the apps again.
    var needsRepick: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \StudySession.whitelist)
    var sessions: [StudySession] = []

    init(id: UUID = UUID(), name: String, selection: FamilyActivitySelection = FamilyActivitySelection(), allowedAppKeys: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.selectionData = TokenCoding.encode(selection)
        self.allowedAppKeys = allowedAppKeys.map(AppKey.normalize)
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var selection: FamilyActivitySelection {
        get { TokenCoding.decode(FamilyActivitySelection.self, from: selectionData) ?? FamilyActivitySelection() }
        set {
            selectionData = TokenCoding.encode(newValue)
            updatedAt = Date()
        }
    }
}

// MARK: - StudySession

@Model
final class StudySession {
    @Attribute(.unique) var id: UUID
    /// Set AFTER inserting the session into a context (setting relationships in
    /// `init` before insertion is unreliable on iOS 17).
    var whitelist: Whitelist?
    var whitelistID: UUID?
    /// Snapshot of the whitelist name (survives whitelist deletion).
    var whitelistName: String
    var startedAt: Date
    /// `nil` = until stopped.
    var plannedEnd: Date?
    var endedAt: Date?
    var endedEarly: Bool

    init(id: UUID = UUID(), whitelistID: UUID?, whitelistName: String, startedAt: Date = Date(), plannedEnd: Date?) {
        self.id = id
        self.whitelist = nil
        self.whitelistID = whitelistID
        self.whitelistName = whitelistName
        self.startedAt = startedAt
        self.plannedEnd = plannedEnd
        self.endedAt = nil
        self.endedEarly = false
    }

    var isRunning: Bool { endedAt == nil }

    /// Focus minutes so far (or total once ended).
    func focusMinutes(at now: Date = Date()) -> Int {
        let end = endedAt ?? min(now, plannedEnd ?? now)
        return max(0, Int(end.timeIntervalSince(startedAt) / 60))
    }
}

// MARK: - UsageSession

enum UsageSource: String, Codable, Sendable {
    /// Logged by `LogAppEventIntent` from a Shortcuts automation.
    case shortcuts
    /// Synthesized (e.g. from a granted unlock window).
    case unlockWindow
}

/// One app-open → app-close span (Shortcuts engine tracker).
@Model
final class UsageSession {
    @Attribute(.unique) var id: UUID
    var appName: String
    var appKey: String
    var start: Date
    /// `nil` while the app is (believed to be) open.
    var end: Date?
    var sourceRaw: String

    init(id: UUID = UUID(), appName: String, start: Date, end: Date? = nil, source: UsageSource = .shortcuts) {
        self.id = id
        self.appName = appName
        self.appKey = AppKey.normalize(appName)
        self.start = start
        self.end = end
        self.sourceRaw = source.rawValue
    }

    var source: UsageSource { UsageSource(rawValue: sourceRaw) ?? .shortcuts }

    var record: UsageRecord {
        UsageRecord(appName: appName, appKey: appKey, start: start, end: end)
    }
}

// MARK: - UnlockEvent

/// Every unlock request outcome (chat grants, declines, emergencies).
@Model
final class UnlockEvent {
    @Attribute(.unique) var id: UUID
    var appName: String
    var appKey: String?
    /// What the user typed / picked.
    var reason: String
    /// `ReasonCategory.rawValue`
    var categoryRaw: String
    var minutes: Int
    var granted: Bool
    var isEmergency: Bool
    /// `true` if this unlock went past the daily free allowance and cost a life.
    var costLife: Bool
    var date: Date

    init(id: UUID = UUID(), appName: String, appKey: String?, reason: String, categoryRaw: String, minutes: Int, granted: Bool, isEmergency: Bool = false, costLife: Bool = false, date: Date = Date()) {
        self.id = id
        self.appName = appName
        self.appKey = appKey
        self.reason = reason
        self.categoryRaw = categoryRaw
        self.minutes = minutes
        self.granted = granted
        self.isEmergency = isEmergency
        self.costLife = costLife
        self.date = date
    }
}

// MARK: - InterruptionEvent

enum InterruptionSource: String, Codable, Sendable {
    /// `CheckAccessIntent` returned false (Shortcuts engine).
    case checkAccess
    /// The Gate screen was shown.
    case gate
    /// The FamilyControls shield (ingested from SharedStore daily counter).
    case shield
}

/// A blocked attempt to open an app ("blocked interruptions" in Stats).
@Model
final class InterruptionEvent {
    @Attribute(.unique) var id: UUID
    var appName: String
    var date: Date
    var sourceRaw: String
    /// How many attempts this row represents (shield counters are ingested in bulk).
    var count: Int

    init(id: UUID = UUID(), appName: String, date: Date = Date(), source: InterruptionSource, count: Int = 1) {
        self.id = id
        self.appName = appName
        self.date = date
        self.sourceRaw = source.rawValue
        self.count = count
    }
}

// MARK: - CompanionState

/// Singleton row (`key == "main"`) holding Bobbly's mood, lives and streak.
@Model
final class CompanionState {
    @Attribute(.unique) var key: String
    /// 0...100
    var mood: Int
    /// 0...maxLives (3); refilled every day.
    var lives: Int
    /// Start of the day the counters below belong to.
    var day: Date
    var focusMinutesToday: Int
    var livesLostToday: Int
    var currentStreak: Int
    var bestStreak: Int
    /// Last time protected time was credited as focus (prevents double counting).
    var lastFocusCreditAt: Date?
    var passiveFocusMinutesToday: Int = 0
    var resistedToday: Int = 0
    var lastResistedAt: Date?

    static let mainKey = "main"

    init(values: CompanionValues = .fresh(day: Calendar.current.startOfDay(for: Date()))) {
        self.key = CompanionState.mainKey
        self.mood = values.mood
        self.lives = values.lives
        self.day = values.day
        self.focusMinutesToday = values.focusMinutesToday
        self.livesLostToday = values.livesLostToday
        self.currentStreak = values.currentStreak
        self.bestStreak = values.bestStreak
        self.lastFocusCreditAt = values.lastFocusCreditAt
        self.passiveFocusMinutesToday = values.passiveFocusMinutesToday
        self.resistedToday = values.resistedToday
        self.lastResistedAt = values.lastResistedAt
    }

    var values: CompanionValues {
        get {
            var result = CompanionValues(mood: mood, lives: lives, day: day, focusMinutesToday: focusMinutesToday,
                                         livesLostToday: livesLostToday, currentStreak: currentStreak,
                                         bestStreak: bestStreak, lastFocusCreditAt: lastFocusCreditAt)
            result.passiveFocusMinutesToday = passiveFocusMinutesToday
            result.resistedToday = resistedToday
            result.lastResistedAt = lastResistedAt
            return result
        }
        set {
            mood = newValue.mood
            lives = newValue.lives
            day = newValue.day
            focusMinutesToday = newValue.focusMinutesToday
            livesLostToday = newValue.livesLostToday
            currentStreak = newValue.currentStreak
            bestStreak = newValue.bestStreak
            lastFocusCreditAt = newValue.lastFocusCreditAt
            passiveFocusMinutesToday = newValue.passiveFocusMinutesToday
            resistedToday = newValue.resistedToday
            lastResistedAt = newValue.lastResistedAt
        }
    }
}
