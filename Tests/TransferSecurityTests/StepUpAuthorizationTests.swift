//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferPersistence
import TransferSecurity
import XCTest

@MainActor
final class StepUpAuthorizationTests: XCTestCase {
    func test_successfulStepUp_forwardsOriginalTransferOnce() async throws {
        let transfer = try SecurityFixtures.transfer()
        let store = CredentialStoreStub(
            credential: try SecurityFixtures.credential()
        )
        let authenticator = StepUpAuthenticatorStub()
        let underlying = SubmissionGatewaySpy()
        let gateway = makeGateway(
            store: store,
            authenticator: authenticator,
            underlying: underlying
        )

        let result = try await gateway.submit(transfer)
        let submissions = await underlying.submissions

        XCTAssertEqual(result, .accepted)
        XCTAssertEqual(authenticator.callCount, 1)
        XCTAssertEqual(submissions, [transfer])
    }

    func test_failedOrCancelledStepUp_blocksSubmission() async throws {
        let failures: [any Error] = [
            StepUpError.failed,
            StepUpError.cancelled,
            SensitiveFailure(),
            CancellationError(),
        ]

        for failure in failures {
            let store = CredentialStoreStub(
                credential: try SecurityFixtures.credential()
            )
            let authenticator = StepUpAuthenticatorStub {
                throw failure
            }
            let underlying = SubmissionGatewaySpy()
            let gateway = makeGateway(
                store: store,
                authenticator: authenticator,
                underlying: underlying
            )

            do {
                _ = try await gateway.submit(
                    SecurityFixtures.transfer()
                )
                XCTFail("Expected step-up to block submission.")
            } catch {
                if failure is CancellationError {
                    XCTAssertTrue(error is CancellationError)
                } else {
                    let expected = failure as? StepUpError ?? .failed
                    XCTAssertEqual(error as? StepUpError, expected)
                }

                XCTAssertFalse(
                    String(reflecting: error).contains(SecurityFixtures.secret)
                )
            }

            let submissions = await underlying.submissions
            XCTAssertTrue(submissions.isEmpty)
        }
    }

    func test_sessionExpiringDuringStepUp_blocksSubmission() async throws {
        let clock = SecurityClock()
        let store = CredentialStoreStub(
            credential: try SecurityFixtures.credential()
        )
        let authenticator = StepUpAuthenticatorStub {
            await clock.set(Date(timeIntervalSince1970: 200))
        }
        let underlying = SubmissionGatewaySpy()
        let gateway = StepUpTransferGateway(
            sessions: SessionProvider(
                store: store,
                now: { await clock.now() }
            ),
            expectedIdentity: SecurityFixtures.identity,
            authenticator: authenticator,
            underlying: underlying
        )

        do {
            _ = try await gateway.submit(SecurityFixtures.transfer())
            XCTFail("Expected the expired session to block submission.")
        } catch {
            XCTAssertEqual(error as? SessionError, .expiredSession)
        }

        let submissions = await underlying.submissions
        XCTAssertEqual(authenticator.callCount, 1)
        XCTAssertTrue(submissions.isEmpty)
    }

    func test_sessionReplacementOrLogoutDuringStepUp_blocksSubmission() async throws {
        let cases: [(SessionCredential?, SessionError)] = [
            (try SecurityFixtures.credential(), .sessionChanged),
            (nil, .missingSession),
        ]

        for (replacement, expectedError) in cases {
            let store = CredentialStoreStub(
                credential: try SecurityFixtures.credential()
            )
            let authenticator = StepUpAuthenticatorStub {
                if let replacement {
                    try await store.save(replacement)
                } else {
                    try await store.delete()
                }
            }
            let underlying = SubmissionGatewaySpy()
            let gateway = makeGateway(
                store: store,
                authenticator: authenticator,
                underlying: underlying
            )

            do {
                _ = try await gateway.submit(SecurityFixtures.transfer())
                XCTFail("Expected the changed session to block submission.")
            } catch {
                XCTAssertEqual(error as? SessionError, expectedError)
            }

            let submissions = await underlying.submissions
            XCTAssertTrue(submissions.isEmpty)
        }
    }

    func test_expiredSession_preservesJournaledIntentWithoutSubmission() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL = directory.appendingPathComponent("journal.sqlite")
        let transfer = try SecurityFixtures.transfer()
        let store = CredentialStoreStub(
            credential: try SecurityFixtures.credential(
                expiresAt: SecurityFixtures.now
            )
        )
        let authenticator = StepUpAuthenticatorStub()
        let underlying = SubmissionGatewaySpy()
        let gateway = makeGateway(
            store: store,
            authenticator: authenticator,
            underlying: underlying
        )
        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let coordinator = TransferCoordinator(
            journal: journal,
            gateway: gateway,
            makeIdempotencyKey: { transfer.idempotencyKey }
        )

        let state = try await coordinator.submit(transfer.intent)

        let reopenedJournal = try CoreDataTransferJournal(storeURL: storeURL)
        let persisted = try await reopenedJournal.entry(
            for: transfer.intent.id
        )
        let submissions = await underlying.submissions

        // The existing coordinator maps every gateway error to unknown.
        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(persisted, transfer)
        XCTAssertEqual(authenticator.callCount, 0)
        XCTAssertTrue(submissions.isEmpty)
    }

    private func makeGateway(
        store: CredentialStoreStub,
        authenticator: StepUpAuthenticatorStub,
        underlying: SubmissionGatewaySpy
    ) -> StepUpTransferGateway {
        StepUpTransferGateway(
            sessions: SessionProvider(
                store: store,
                now: { SecurityFixtures.now }
            ),
            expectedIdentity: SecurityFixtures.identity,
            authenticator: authenticator,
            underlying: underlying
        )
    }
}
