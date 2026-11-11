//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferSimulation
import XCTest

@MainActor
final class AmbiguousOutcomeTests: XCTestCase {
    func test_timeoutThenOutage_preservesIdentityUntilSettlementIsConfirmed() async throws {
        try await IntegrationFixtures.withJournal { _, journal in
            let transfer = try IntegrationFixtures.transfer()
            let store = SimulatedTransferStore()
            let bank = SimulatedBank(
                store: store,
                faults: [transfer.idempotencyKey: .timeoutAfterCommit]
            )
            let submissions = IntegrationSubmissionSpy(underlying: bank)
            let coordinator = TransferCoordinator(
                journal: journal,
                gateway: submissions,
                makeIdempotencyKey: { transfer.idempotencyKey }
            )

            let submissionState = try await coordinator.submit(
                transfer.intent
            )
            XCTAssertEqual(submissionState, .unknown)

            let statusGateway = OutageStatusGateway(underlying: bank)
            let service = TransferReconciliationService(
                journal: journal,
                gateway: statusGateway,
                policy: try ReconciliationPolicy(
                    maximumAttempts: 3,
                    retryDelayNanoseconds: 0
                ),
                sleep: { _ in }
            )

            let outageResult = try await service.reconcile(
                intentID: transfer.intent.id
            )
            let persistedDuringOutage = try await journal.entry(
                for: transfer.intent.id
            )
            let outageLookups = await statusGateway.lookups

            XCTAssertEqual(outageResult, .unresolved(attempts: 3))
            XCTAssertEqual(persistedDuringOutage, transfer)
            XCTAssertEqual(outageLookups.count, 3)

            _ = try await store.advanceStatus(
                for: transfer.idempotencyKey,
                to: .settled
            )
            await statusGateway.setAvailable(true)

            let recoveredResult = try await service.reconcile(
                intentID: transfer.intent.id
            )
            let requests = await submissions.submissions
            let acceptedCount = await store.acceptedTransferCount
            let allLookups = await statusGateway.lookups

            XCTAssertEqual(
                recoveredResult,
                .confirmed(state: .settled, attempts: 1)
            )
            XCTAssertEqual(requests, [transfer])
            XCTAssertEqual(acceptedCount, 1)
            XCTAssertEqual(
                allLookups,
                Array(
                    repeating: OutageStatusGateway.Lookup(
                        intentID: transfer.intent.id,
                        idempotencyKey: transfer.idempotencyKey
                    ),
                    count: 4
                )
            )
        }
    }

    func test_replayedOlderAndDuplicateBankResponses_doNotRegressSettlement() async throws {
        try await IntegrationFixtures.withJournal { _, journal in
            let transfer = try IntegrationFixtures.transfer()
            let store = SimulatedTransferStore()
            let bank = SimulatedBank(store: store)
            let coordinator = TransferCoordinator(
                journal: journal,
                gateway: bank,
                makeIdempotencyKey: { transfer.idempotencyKey }
            )

            _ = try await coordinator.submit(transfer.intent)

            let acceptedResponse = try await bank.status(
                for: transfer.intent.id,
                idempotencyKey: transfer.idempotencyKey
            )
            _ = try await store.advanceStatus(
                for: transfer.idempotencyKey,
                to: .settled
            )
            let settledResponse = try await bank.status(
                for: transfer.intent.id,
                idempotencyKey: transfer.idempotencyKey
            )

            // Replay real simulator responses in delivery order.
            let gateway = ReplayedStatusGateway(
                responses: [
                    settledResponse,
                    acceptedResponse,
                    settledResponse,
                ]
            )
            let service = TransferReconciliationService(
                journal: journal,
                gateway: gateway,
                policy: try ReconciliationPolicy(maximumAttempts: 1)
            )

            for _ in 0..<3 {
                let result = try await service.reconcile(
                    intentID: transfer.intent.id
                )

                XCTAssertEqual(
                    result,
                    .confirmed(state: .settled, attempts: 1)
                )
            }

            let latest = await service.latestStatus(
                for: transfer.intent.id
            )
            let persisted = try await journal.entry(
                for: transfer.intent.id
            )
            let acceptedCount = await store.acceptedTransferCount

            XCTAssertEqual(latest?.state, .settled)
            XCTAssertEqual(latest?.version, settledResponse.version)
            XCTAssertEqual(persisted, transfer)
            XCTAssertEqual(acceptedCount, 1)
        }
    }
}

private enum StatusTestError: Error {
    case unavailable
}

private actor OutageStatusGateway: TransferStatusGateway {
    struct Lookup: Equatable, Sendable {
        let intentID: UUID
        let idempotencyKey: UUID
    }

    private let underlying: any TransferStatusGateway
    private var isAvailable = false
    private(set) var lookups: [Lookup] = []

    init(underlying: any TransferStatusGateway) {
        self.underlying = underlying
    }

    func setAvailable(_ value: Bool) {
        isAvailable = value
    }

    func status(
        for intentID: UUID,
        idempotencyKey: UUID
    ) async throws -> TransferStatusResponse {
        lookups.append(
            Lookup(intentID: intentID, idempotencyKey: idempotencyKey)
        )

        guard isAvailable else {
            throw StatusTestError.unavailable
        }

        return try await underlying.status(
            for: intentID,
            idempotencyKey: idempotencyKey
        )
    }
}

private actor ReplayedStatusGateway: TransferStatusGateway {
    private var responses: [TransferStatusResponse]

    init(responses: [TransferStatusResponse]) {
        self.responses = responses
    }

    func status(
        for intentID: UUID,
        idempotencyKey: UUID
    ) async throws -> TransferStatusResponse {
        guard !responses.isEmpty else {
            throw StatusTestError.unavailable
        }

        return responses.removeFirst()
    }
}
