//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain
import TransferSecurity
import XCTest

final class SecurityFailureTests: XCTestCase {
    func test_sessionErrors_distinguishSignInFromCredentialAccessFailure() {
        let sessionErrors: [SessionError] = [
            .invalidCredential,
            .missingSession,
            .expiredSession,
            .identityMismatch,
            .sessionChanged,
        ]

        for error in sessionErrors {
            XCTAssertEqual(
                error.transferFailure,
                .authenticationRequired
            )
            XCTAssertEqual(
                error.transferFailure.suggestedAction,
                .signIn
            )
        }

        let unavailable = SessionError.credentialUnavailable.transferFailure

        XCTAssertEqual(unavailable, .authenticationUnavailable)
        XCTAssertEqual(
            unavailable.suggestedAction,
            .checkAuthenticationAvailability
        )
    }

    func test_stepUpErrors_preserveDifferentRecoveryActions() {
        let cases: [
            (StepUpError, TransferFailure, TransferFailureAction)
        ] = [
            (.failed, .stepUpRequired, .authenticate),
            (.alreadyInProgress, .stepUpRequired, .authenticate),
            (.cancelled, .cancelled, .reconcile),
            (
                .unavailable,
                .authenticationUnavailable,
                .checkAuthenticationAvailability
            ),
            (
                .invalidReason,
                .configurationFailure,
                .reviewConfiguration
            ),
        ]

        for (error, expectedFailure, expectedAction) in cases {
            XCTAssertEqual(error.transferFailure, expectedFailure)
            XCTAssertEqual(
                error.transferFailure.suggestedAction,
                expectedAction
            )
        }
    }
}
