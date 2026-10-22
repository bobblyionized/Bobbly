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

enum AuthorizationRules {
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
        /// Authorized → (re)activate FamilyControls.
        case activate
        /// Definitely revoked → void tokens, fall back to Shortcuts.
        case revoked
        /// Unclear → keep FamilyControls and its shields untouched; retry later.
        case keepAndRetry
    }

    static func afterSilentReRequest(_ result: AuthorizationRequestResult, statusAfter: Status) -> SilentRecovery {
        switch result {
        case .approved:
            return .activate
        case .userDenied:
            return .revoked
        case .failed:
            switch statusAfter {
            case .approved: return .activate
            case .denied: return .revoked
            case .notDetermined: return .keepAndRetry
            }
        }
    }

    enum UserRequestOutcome: Equatable, Sendable {
        case activate
        /// Switch to Shortcuts; `invalidateTokens` when access was definitely
        /// withdrawn from a previously working FamilyControls setup.
        case fallback(invalidateTokens: Bool)
        /// A previously working FamilyControls setup hit a transient error:
        /// don't switch engines (switching would clear the shields).
        case keepFamilyControls
    }

    /// After a user-initiated request (tutorial, Settings › Retry, reattach).
    static func afterUserRequest(_ result: AuthorizationRequestResult, wasFamily: Bool) -> UserRequestOutcome {
        switch result {
        case .approved: return .activate
        case .userDenied: return .fallback(invalidateTokens: wasFamily)
        case .failed: return wasFamily ? .keepFamilyControls : .fallback(invalidateTokens: false)
        }
    }
}
