import XCTest
import FamilyControls
@testable import Bobbly

final class AuthorizationRulesTests: XCTestCase {

    func testErrorMapping() {
        XCTAssertEqual(AuthorizationRequestResult(error: FamilyControlsError.authorizationCanceled), .userDenied)
        if case .failed = AuthorizationRequestResult(error: FamilyControlsError.networkError) {} else {
            XCTFail("network errors are not a denial")
        }
        if case .failed = AuthorizationRequestResult(error: NSError(domain: "x", code: 1)) {} else {
            XCTFail("unknown errors are not a denial")
        }
    }

    func testStatusMirror() {
        XCTAssertEqual(AuthorizationRules.Status(.approved), .approved)
        XCTAssertEqual(AuthorizationRules.Status(.denied), .denied)
        XCTAssertEqual(AuthorizationRules.Status(.notDetermined), .notDetermined)
    }

    func testSilentReRequestOnlyForPreviouslyWorkingSetup() {
        XCTAssertTrue(AuthorizationRules.shouldSilentlyReRequest(wasFamily: true, status: .notDetermined, prefersShortcuts: false))
        XCTAssertFalse(AuthorizationRules.shouldSilentlyReRequest(wasFamily: false, status: .notDetermined, prefersShortcuts: false))
        XCTAssertFalse(AuthorizationRules.shouldSilentlyReRequest(wasFamily: true, status: .approved, prefersShortcuts: false))
        XCTAssertFalse(AuthorizationRules.shouldSilentlyReRequest(wasFamily: true, status: .denied, prefersShortcuts: false))
        XCTAssertFalse(AuthorizationRules.shouldSilentlyReRequest(wasFamily: true, status: .notDetermined, prefersShortcuts: true))
    }

    func testTokensAreOnlyVoidedOnDefiniteSignals() {
        XCTAssertTrue(AuthorizationRules.isDefiniteRevocation(wasFamily: true, status: .denied, request: nil))
        XCTAssertTrue(AuthorizationRules.isDefiniteRevocation(wasFamily: true, status: .notDetermined, request: .userDenied))
        // A stale/unclear read is not a revocation.
        XCTAssertFalse(AuthorizationRules.isDefiniteRevocation(wasFamily: true, status: .notDetermined, request: nil))
        XCTAssertFalse(AuthorizationRules.isDefiniteRevocation(wasFamily: true, status: .notDetermined, request: .failed("unavailable")))
        // Nothing to void if FamilyControls was never in use.
        XCTAssertFalse(AuthorizationRules.isDefiniteRevocation(wasFamily: false, status: .denied, request: .userDenied))
    }

    /// A silent no-op: fast, app never left the foreground.
    private func silent(_ result: AuthorizationRequestResult) -> AuthorizationAttempt {
        AuthorizationAttempt(result: result, duration: 0.05, resignedActive: false)
    }

    /// The system prompt was shown and answered by a human.
    private func prompted(_ result: AuthorizationRequestResult) -> AuthorizationAttempt {
        AuthorizationAttempt(result: result, duration: 4, resignedActive: true)
    }

    func testFailedSilentReRequestKeepsFamilyControls() {
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(silent(.approved), statusAfter: .notDetermined), .activate)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(silent(.failed("x")), statusAfter: .approved), .activate)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(silent(.failed("x")), statusAfter: .notDetermined), .keepAndRetry)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(silent(.failed("x")), statusAfter: .denied), .revoked)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(silent(.userDenied), statusAfter: .notDetermined), .revoked)
    }

    func testInteractiveDetectionNeedsBothSignals() {
        XCTAssertTrue(AuthorizationRules.wasInteractive(prompted(.approved)))
        XCTAssertFalse(AuthorizationRules.wasInteractive(silent(.approved)))
        // Slow but never left the foreground (busy device at cold launch).
        XCTAssertFalse(AuthorizationRules.wasInteractive(AuthorizationAttempt(result: .approved, duration: 5, resignedActive: false)))
        // Left the foreground briefly (Control Center) during a fast silent call.
        XCTAssertFalse(AuthorizationRules.wasInteractive(AuthorizationAttempt(result: .approved, duration: 0.2, resignedActive: true)))
    }

    func testReApprovalAfterRealRevocationVoidsSavedPicks() {
        // Revoked in iOS Settings → the silent re-request actually prompted → approved again.
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(prompted(.approved), statusAfter: .approved), .reapproved)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(prompted(.failed("x")), statusAfter: .approved), .reapproved)
        // A prompt that ended in cancel is a definite revocation.
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(prompted(.userDenied), statusAfter: .notDetermined), .revoked)
    }

    func testUserInitiatedRequestOutcomes() {
        XCTAssertEqual(AuthorizationRules.afterUserRequest(silent(.approved), wasFamily: false), .activate)
        // First-time setup always prompts; nothing saved to void.
        XCTAssertEqual(AuthorizationRules.afterUserRequest(prompted(.approved), wasFamily: false), .activate)
        // Settings › Retry on a setup that had lost access and is re-approved via the prompt.
        XCTAssertEqual(AuthorizationRules.afterUserRequest(prompted(.approved), wasFamily: true), .activateWithFreshPicks)
        XCTAssertEqual(AuthorizationRules.afterUserRequest(silent(.approved), wasFamily: true), .activate)
        XCTAssertEqual(AuthorizationRules.afterUserRequest(silent(.failed("x")), wasFamily: false), .fallback(invalidateTokens: false))
        XCTAssertEqual(AuthorizationRules.afterUserRequest(prompted(.userDenied), wasFamily: false), .fallback(invalidateTokens: false))
        XCTAssertEqual(AuthorizationRules.afterUserRequest(prompted(.userDenied), wasFamily: true), .fallback(invalidateTokens: true))
        // Transient error on a working setup: don't switch engines (that would clear shields).
        XCTAssertEqual(AuthorizationRules.afterUserRequest(silent(.failed("x")), wasFamily: true), .keepFamilyControls)
    }

    func testRetryButtonVisibility() {
        XCTAssertFalse(AuthorizationRules.canRetryScreenTime(state: .familyControls, isAuthorized: true))
        // Kept on FamilyControls after an unclear re-request, but not authorized.
        XCTAssertTrue(AuthorizationRules.canRetryScreenTime(state: .familyControls, isAuthorized: false))
        XCTAssertTrue(AuthorizationRules.canRetryScreenTime(state: .shortcutsFallback(reason: "x"), isAuthorized: false))
        XCTAssertTrue(AuthorizationRules.canRetryScreenTime(state: .detached, isAuthorized: false))
        XCTAssertTrue(AuthorizationRules.canRetryScreenTime(state: .undetermined, isAuthorized: false))
    }

    @MainActor
    func testSuccessfulDetachMakesReattachAFreshSetup() {
        // What FamilyControlsEngine.detach leaves behind after a successful revoke.
        let shared = SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
        shared.engineKind = .familyControls
        shared.invalidateTokens()
        shared.engineKind = nil
        // Reattach must not take the "silent re-request of a working setup" path.
        XCTAssertFalse(AuthorizationRules.shouldSilentlyReRequest(wasFamily: shared.engineKind == .familyControls,
                                                                 status: .notDetermined, prefersShortcuts: false))
        // …so a failed request falls back visibly instead of pretending FamilyControls runs.
        XCTAssertEqual(AuthorizationRules.afterUserRequest(silent(.failed("x")), wasFamily: shared.engineKind == .familyControls),
                       .fallback(invalidateTokens: false))
    }

    @MainActor
    func testConcurrentBootstrapsShareOneRun() async {
        let shared = SharedStore(defaults: UserDefaults(suiteName: "bobbly.tests.\(UUID().uuidString)")!)
        let selector = EngineSelector(shared: shared)
        async let a: Void = selector.bootstrap(requestIfNeeded: false)
        async let b: Void = selector.bootstrap(requestIfNeeded: false)
        _ = await (a, b)
        // Fresh store, simulator not authorized: stays undetermined, nothing invalidated.
        XCTAssertEqual(selector.state, .undetermined)
        XCTAssertNil(shared.tokensRevokedAt)
    }
}
