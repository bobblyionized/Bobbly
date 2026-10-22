//  QuickSetup.swift
//  Bobbly/Engine — the one-automation Shortcuts setup ("Quick setup").
//
//  One personal automation covers every distracting app:
//  "When <apps…> Is Opened → Run Immediately → Bobbly Gate". The trigger
//  doesn't say which app opened, so Bobbly treats them as one GROUP
//  (`AppKey.group`): one access decision, one unlock, one usage bucket.
//  Needs iOS 26 (the Gate intent brings Bobbly forward with
//  `continueInForeground`). Older iOS keeps the per-app setup.

import Foundation

/// How the Shortcuts engine is set up.
enum SetupMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// One automation for all apps, one "Bobbly Gate" action (iOS 26+).
    case quick
    /// Two automations per app with Check Access + If + Open URL (advanced / iOS < 26).
    case perApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "Quick setup"
        case .perApp: return "Per-app setup"
        }
    }

    var subtitle: String {
        switch self {
        case .quick: return "One automation for all your apps. No typing."
        case .perApp: return "Two automations per app. Tracks each app separately."
        }
    }

    /// Default: quick wherever it's supported.
    static var recommended: SetupMode { QuickSetup.isAvailable ? .quick : .perApp }
}

/// Instructions + names for the quick setup.
enum QuickSetup {
    /// The Gate intent needs iOS 26 (`supportedModes` / `continueInForeground`).
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// Action names exactly as they appear in the Shortcuts app.
    static let gateActionName = "Bobbly Gate"
    static let closedActionName = "Bobbly: App Closed"

    /// The one required automation.
    static let steps: [String] = [
        "Open the Shortcuts app › Automation › + (New Automation).",
        "Choose App, tap Choose and select every distracting app at once, then tap Done.",
        "Tick \"Is Opened\" (only), choose \"Run Immediately\", then tap Next.",
        "Tap \"New Blank Automation\", search \"Bobbly\" and add \"Bobbly Gate\".",
        "Leave App empty and tap Done. That's it: open one of those apps to test it.",
    ]

    /// Optional second automation — only needed for usage time in Stats/Search.
    static let optionalTrackingSteps: [String] = [
        "Optional, for usage time: + › App › Choose the same apps.",
        "Tick \"Is Closed\" (only), choose \"Run Immediately\", then Next › New Blank Automation.",
        "Add \"Bobbly: App Closed\" and tap Done.",
    ]
}

/// Live "Test it" status for the quick setup (tutorial ✅ / Settings).
struct QuickSetupStatus: Equatable, Sendable {
    /// Times "Bobbly Gate" ran (from any automation).
    var gateRuns: Int
    var lastGateRunAt: Date?
    /// Times "Bobbly: App Closed" ran.
    var closedRuns: Int
    var lastClosedRunAt: Date?

    /// ✅ "Automation detected".
    var isDetected: Bool { gateRuns > 0 }
    /// The optional "Is Closed" automation is set up → usage time is tracked.
    var tracksUsageTime: Bool { closedRuns > 0 }

    init(_ stats: QuickSetupRunStats) {
        gateRuns = stats.gateRuns
        lastGateRunAt = stats.lastGateRunAt
        closedRuns = stats.closedRuns
        lastClosedRunAt = stats.lastClosedRunAt
    }
}
