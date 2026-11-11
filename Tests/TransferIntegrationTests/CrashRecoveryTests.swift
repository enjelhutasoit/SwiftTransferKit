//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferPersistence
import TransferSimulation
import XCTest

@MainActor
final class CrashRecoveryTests: XCTestCase {
    func test_preparedButUnsentIntent_remainsUnresolvedAfterClientRecreation() async throws {
        try await IntegrationFixtures.withJournal { storeURL, journal in
            let transfer = try IntegrationFixtures.transfer()

            // Model interruption after persistence and before gateway submission.
            _ = try await journal.record(
                transfer.intent,
                idempotencyKey: transfer.idempotencyKey
            )

            let reopenedJournal = try CoreDataTransferJournal(
                storeURL: storeURL
            )
            let store = SimulatedTransferStore()
            let bank = SimulatedBank(store: store)
            let submissions = IntegrationSubmissionSpy(underlying: bank)
            let differentCandidateKey = UUID(
                uuidString: "00000000-0000-4000-8000-000000000099"
            )!
            let recreatedCoordinator = TransferCoordinator(
                journal: reopenedJournal,
                gateway: submissions,
                makeIdempotencyKey: { differentCandidateKey }
            )

            let state = try await recreatedCoordinator.submit(
                transfer.intent
            )
            let recovery = TransferRecoveryService(
                journal: reopenedJournal,
                gateway: bank,
                policy: try ReconciliationPolicy(maximumAttempts: 1)
            )
            let report = try await recovery.recover()

            let recovered = try XCTUnwrap(report.first)
            let persisted = try await reopenedJournal.entry(
                for: transfer.intent.id
            )
            let requests = await submissions.submissions
            let acceptedCount = await store.acceptedTransferCount

            XCTAssertEqual(state, .unknown)
            XCTAssertEqual(report.count, 1)
            XCTAssertEqual(recovered.entry, transfer)
            XCTAssertEqual(
                recovered.reconciliation,
                .unresolved(attempts: 1)
            )
            XCTAssertEqual(recovered.classification, .unresolved)
            XCTAssertEqual(persisted, transfer)
            XCTAssertTrue(requests.isEmpty)
            XCTAssertEqual(acceptedCount, 0)
        }
    }
}
