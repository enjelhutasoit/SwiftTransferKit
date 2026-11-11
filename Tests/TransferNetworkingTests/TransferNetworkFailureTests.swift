//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain
import TransferNetworking
import XCTest

final class TransferNetworkFailureTests: XCTestCase {
    func test_httpAuthenticationAndTransportFailures_haveDifferentActions() {
        let cases: [
            (
                TransferNetworkError,
                TransferFailure,
                TransferFailureAction
            )
        ] = [
            (
                .unexpectedHTTPStatus(401),
                .authenticationRequired,
                .signIn
            ),
            (
                .unexpectedHTTPStatus(403),
                .authorizationDenied,
                .reviewAccess
            ),
            (
                .timedOut,
                .transportFailure,
                .reconcile
            ),
            (
                .transportFailure,
                .transportFailure,
                .reconcile
            ),
            (
                .invalidResponse,
                .invalidResponse,
                .reconcile
            ),
            (
                .unexpectedHTTPStatus(500),
                .invalidResponse,
                .reconcile
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
