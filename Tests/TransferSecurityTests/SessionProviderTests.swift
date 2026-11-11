//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferSecurity
import XCTest

@MainActor
final class SessionProviderTests: XCTestCase {
    func test_validSession_returnsStoredCredential() async throws {
        let credential = try SecurityFixtures.credential()
        let store = CredentialStoreStub(credential: credential)
        let provider = SessionProvider(
            store: store,
            now: { SecurityFixtures.now }
        )

        let result = try await provider.validSession(
            for: SecurityFixtures.identity
        )

        XCTAssertEqual(result, credential)
    }

    func test_missingExpiredAndWrongIdentitySessions_areBlocked() async throws {
        let otherIdentity = SessionIdentity(
            organizationID: SecurityFixtures.identity.organizationID,
            userID: UUID()
        )

        let cases: [(SessionCredential?, SessionError)] = [
            (nil, .missingSession),
            (
                try SecurityFixtures.credential(
                    expiresAt: SecurityFixtures.now
                ),
                .expiredSession
            ),
            (
                try SecurityFixtures.credential(identity: otherIdentity),
                .identityMismatch
            ),
        ]

        for (credential, expectedError) in cases {
            let provider = SessionProvider(
                store: CredentialStoreStub(credential: credential),
                now: { SecurityFixtures.now }
            )

            do {
                _ = try await provider.validSession(
                    for: SecurityFixtures.identity
                )
                XCTFail("Expected the session to be blocked.")
            } catch {
                XCTAssertEqual(error as? SessionError, expectedError)
            }
        }
    }

    func test_storeFailure_doesNotExposeUnderlyingError() async {
        let provider = SessionProvider(
            store: CredentialStoreStub(
                credential: nil,
                failsToLoad: true
            ),
            now: { SecurityFixtures.now }
        )

        do {
            _ = try await provider.validSession(
                for: SecurityFixtures.identity
            )
            XCTFail("Expected credential access to fail.")
        } catch {
            XCTAssertEqual(
                error as? SessionError,
                .credentialUnavailable
            )
            XCTAssertFalse(
                String(reflecting: error).contains(SecurityFixtures.secret)
            )
        }
    }

    func test_credentialDescriptions_doNotExposeToken() throws {
        let credential = try SecurityFixtures.credential()
        var dumpOutput = ""
        dump(credential, to: &dumpOutput)

        let outputs = [
            String(describing: credential),
            String(reflecting: credential),
            dumpOutput,
        ]

        for output in outputs {
            XCTAssertFalse(output.contains(SecurityFixtures.secret))
            XCTAssertTrue(output.contains("<redacted>"))
        }
    }
}
