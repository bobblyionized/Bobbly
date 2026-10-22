//  AuthorizationRules.swift
//  Bobbly/Engine — pure decision rules for Screen Time authorization
//  recovery (unit-tested). EngineSelector applies them.
//
//  Principles:
//   • Saved tokens are voided ONLY on a definite signal: status `.denied`, or
//     the user explicitly cancelling an authorization prompt.
//   • A transient failure (stale `.notDetermined` read at cold launch, network,
//     "unavailable"…) never tears down a working FamilyControls setup: keep the
//     engine and its shields, retry on the next foreground.

import Foundation
import FamilyControls

/// The outcome of an authorization request, abstracted for the rules.
enum AuthorizationRequestResult: Equatable, Sendable {
    case approved
    /// The user explicitly cancelled the prompt (`FamilyControlsError.authorizationCanceled`).
    case userDenied
    /// Anything else — not proof that access was revoked.
    case failed(String)

    init(error: Error) {
        if let familyError = error as? FamilyControlsError, familyError == .authorizationCanceled {
            self = .userDenied
        } else {
            self = .failed(String(describing: error))
        }
    }
}

/// One authorization request plus the evidence of whether the system prompt
/// was actually shown (vs. a silent no-op for an app that is still authorized).
struct AuthorizationAttempt: Equatable, Sendable {
    var result: AuthorizationRequestResult
    /// Seconds the request took.
    var duration: TimeInterval
    /// The app resigned active while the request was in flight — the system
    /// alert / Face ID sheet covering the app does exactly that.
    var resignedActive: Bool
}

enum AuthorizationRules {
    /// A silent re-request returns in milliseconds; a real prompt needs a human.
    static let interactiveMinimumDuration: TimeInterval = 1.0

    /// `true` when the request really showed the Screen Time prompt. Both
    /// signals are required, so a slow silent call or an unrelated
    /// interruption (Control Center) alone never counts as a re-approval —
    /// a false positive here would wipe the user's block list.
    static func wasInteractive(_ attempt: AuthorizationAttempt) -> Bool {
        attempt.resignedActive && attempt.duration >= interactiveMinimumDuration
    }

    /// A plain mirror of `AuthorizationStatus` (unknown future cases count as
    /// `.notDetermined`, i.e. never as a definite revocation).
    enum Status: Equatable, Sendable {
        case approved
        case denied
        case notDetermined

        init(_ status: AuthorizationStatus) {
            switch status {
            case .approved: self = .approved
            case .denied: self = .denied
            case .notDetermined: self = .notDetermined
            @unknown default: self = .notDetermined
            }
        }
    }

    /// Bobbly was running on FamilyControls but the status reads
    /// `.notDetermined` (possibly a stale read): re-request silently first —
    /// that is silent while still authorized and only prompts if access was
    /// really revoked.
    static func shouldSilentlyReRequest(wasFamily: Bool, status: Status, prefersShortcuts: Bool) -> Bool {
        wasFamily && status == .notDetermined && !prefersShortcuts
    }

    /// Only a definite signal voids saved tokens.
    static func isDefiniteRevocation(wasFamily: Bool, status: Status, request: AuthorizationRequestResult?) -> Bool {
        guard wasFamily else { return false }
        return status == .denied || request == .userDenied
    }

    enum SilentRecovery: Equatable, Sendable {
        /// Still authorized (silent no-op) → (re)activate FamilyControls.
        case activate
        /// Access had really been revoked and the user just re-approved it via
        /// the prompt: Apple voided every saved token on revoke → clear the
        /// saved picks (user re-picks), then activate.
        case reapproved
        /// Definitely revoked → void tokens, fall back to Shortcuts.
        case revoked
        /// Unclear → keep FamilyControls and its shields untouched; retry later.
        case keepAndRetry
    }

    static func afterSilentReRequest(_ attempt: AuthorizationAttempt, statusAfter: Status) -> SilentRecovery {
        let approved: Bool
        switch attempt.result {
        case .approved:
            approved = true
        case .userDenied:
            return .revoked
        case .failed:
            switch statusAfter {
            case .approved: approved = true
            case .denied: return .revoked
            case .notDetermined: return .keepAndRetry
            }
        }
        return approved && wasInteractive(attempt) ? .reapproved : .activate
    }

    enum UserRequestOutcome: Equatable, Sendable {
        case activate
        /// A previously working setup had lost access and was re-approved
        /// through the prompt: clear the voided picks, then activate.
        case activateWithFreshPicks
        /// Switch to Shortcuts; `invalidateTokens` when access was definitely
        /// withdrawn from a previously working FamilyControls setup.
        case fallback(invalidateTokens: Bool)
        /// A previously working FamilyControls setup hit a transient error:
        /// don't switch engines (switching would clear the shields).
        case keepFamilyControls
    }

    /// Settings shows "Retry Screen Time access" unless FamilyControls is both
    /// selected and actually authorized.
    static func canRetryScreenTime(state: EngineSelectionState, isAuthorized: Bool) -> Bool {
        state != .familyControls || !isAuthorized
    }

    /// After a user-initiated request (tutorial, Settings › Retry, reattach).
    static func afterUserRequest(_ attempt: AuthorizationAttempt, wasFamily: Bool) -> UserRequestOutcome {
        switch attempt.result {
        case .approved: return wasFamily && wasInteractive(attempt) ? .activateWithFreshPicks : .activate
        case .userDenied: return .fallback(invalidateTokens: wasFamily)
        case .failed: return wasFamily ? .keepFamilyControls : .fallback(invalidateTokens: false)
        }
    }
}
