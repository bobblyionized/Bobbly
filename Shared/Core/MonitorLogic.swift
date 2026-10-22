//  MonitorLogic.swift
//  Shared/Core — what the monitor extension does when a Bobbly trigger
//  activity fires. Kept free of ManagedSettings so it is unit-testable; the
//  extension applies shields afterwards with `ShieldPolicy.reconcile`.

import Foundation
import DeviceActivity

enum MonitorOutcome: Equatable {
    /// Chat unlocks expired and were removed (one trigger covers every grant
    /// that is due, e.g. a multi-app unlock).
    case unlocksEnded([UnlockGrant])
    /// The emergency unblock expired.
    case emergencyEnded
    /// A timed study session finished.
    case studyEnded(whitelistName: String)
    /// Nothing to do (already handled, extended, or not due yet).
    case none

    var logDescription: String {
        switch self {
        case .unlocksEnded(let grants): return "relocked \(grants.map(\.displayName).joined(separator: ", "))"
        case .emergencyEnded: return "emergency over"
        case .studyEnded(let name): return "study '\(name)' over"
        case .none: return "no-op"
        }
    }
}

enum MonitorLogic {
    /// DeviceActivity fires on minute granularity; accept triggers this early.
    static let tolerance: TimeInterval = 90

    /// Ends the state the trigger `activity` stands for, if it is due.
    /// Idempotent: calling it again (e.g. on `intervalDidEnd`) returns `.none`.
    /// If the user extended the state meanwhile (new grant, longer emergency),
    /// it is left alone because it is no longer due.
    static func handle(_ activity: DeviceActivityName, shared: SharedStore, now: Date) -> MonitorOutcome {
        let horizon = now.addingTimeInterval(tolerance)

        if activity.bobblyUnlockGrantID != nil {
            let all = shared.grants
            let due = all.filter { $0.expiresAt <= horizon }
            guard !due.isEmpty else { return .none }
            shared.grants = all.filter { $0.expiresAt > horizon }
            return .unlocksEnded(due)
        }

        if activity == .bobblyEmergency {
            guard let until = shared.emergencyUntil, until <= horizon else { return .none }
            shared.emergencyUntil = nil
            return .emergencyEnded
        }

        if activity == .bobblyStudy {
            guard let study = shared.activeStudy, let end = study.endsAt, end <= horizon else { return .none }
            shared.activeStudy = nil
            shared.lastStudyEndedAt = end
            return .studyEnded(whitelistName: study.whitelistName)
        }

        return .none
    }
}
