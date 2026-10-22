//  GateIntentLogic.swift
//  Bobbly/Engine — pure decisions for `BobblyGateIntent` / `BobblyAppClosedIntent`
//  (unit-tested; the intents only do I/O).

import Foundation

enum GateIntentLogic {
    /// What the Gate intent should do for one "app opened" trigger.
    struct Evaluation: Equatable {
        /// No app name → group mode ("one of your blocked apps").
        var isGroup: Bool
        /// Name passed to `AccessPolicy` (`AppKey.group` in group mode).
        var accessName: String
        /// Name usage/interruptions are logged under ("Blocked apps" in group mode).
        var trackingName: String
        var decision: AccessDecision
        /// `true` → log one interruption and bring up the Gate.
        var showsGate: Bool { !decision.isAllowed }
        /// Log a real open→close session (needs the optional "Is Closed"
        /// automation); otherwise log a zero-length open so Stats counts the
        /// open without inventing time.
        var tracksSessionTime: Bool
    }

    /// Normalizes the optional App parameter (`nil`, empty and "Blocked apps"
    /// all mean group mode).
    static func appName(from parameter: String?) -> String? {
        guard let trimmed = parameter?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        if AppKey.isGroup(trimmed) || AppKey.normalize(trimmed) == AppKey.normalize(AppKey.groupDisplayName) { return nil }
        return trimmed
    }

    static func evaluate(appParameter: String?, snapshot: AccessSnapshot,
                         closedAutomationDetected: Bool, now: Date) -> Evaluation {
        let name = appName(from: appParameter)
        let accessName = name ?? AppKey.group
        return Evaluation(
            isGroup: name == nil,
            accessName: accessName,
            trackingName: name ?? AppKey.groupDisplayName,
            decision: AccessPolicy.decide(appName: accessName, snapshot: snapshot, now: now),
            tracksSessionTime: closedAutomationDetected
        )
    }

    /// How to surface the Gate.
    enum Routing: Equatable {
        /// Access allowed: return immediately, stay in the background.
        case stayInBackground
        /// Bring Bobbly forward (`continueInForeground(alwaysConfirm: false)`) to the Gate.
        case continueInForeground
        /// Foreground not possible right now: post a tap-to-open notification.
        case notifyOnly
    }

    static func routing(showsGate: Bool, canContinueInForeground: Bool) -> Routing {
        guard showsGate else { return .stayInBackground }
        return canContinueInForeground ? .continueInForeground : .notifyOnly
    }

    /// The "Bobbly: App Closed" intent's tracking name (same bucket rules).
    static func closedTrackingName(appParameter: String?) -> String {
        appName(from: appParameter) ?? AppKey.groupDisplayName
    }
}
