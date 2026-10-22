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

    func testFailedSilentReRequestKeepsFamilyControls() {
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(.approved, statusAfter: .notDetermined), .activate)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(.failed("x"), statusAfter: .approved), .activate)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(.failed("x"), statusAfter: .notDetermined), .keepAndRetry)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(.failed("x"), statusAfter: .denied), .revoked)
        XCTAssertEqual(AuthorizationRules.afterSilentReRequest(.userDenied, statusAfter: .notDetermined), .revoked)
    }

    func testUserInitiatedRequestOutcomes() {
        XCTAssertEqual(AuthorizationRules.afterUserRequest(.approved, wasFamily: false), .activate)
        XCTAssertEqual(AuthorizationRules.afterUserRequest(.failed("x"), wasFamily: false), .fallback(invalidateTokens: false))
        XCTAssertEqual(AuthorizationRules.afterUserRequest(.userDenied, wasFamily: false), .fallback(invalidateTokens: false))
        XCTAssertEqual(AuthorizationRules.afterUserRequest(.userDenied, wasFamily: true), .fallback(invalidateTokens: true))
        // Transient error on a working setup: don't switch engines (that would clear shields).
        XCTAssertEqual(AuthorizationRules.afterUserRequest(.failed("x"), wasFamily: true), .keepFamilyControls)
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
