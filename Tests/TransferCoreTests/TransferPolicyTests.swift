//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import XCTest

@MainActor
final class TransferPolicyTests: XCTestCase {
    func test_cachedLimitAdvice_handlesMissingPolicyAndInclusiveBoundary() throws {
        let policy = TransferLimitPolicy(
            maximumPerTransfer: try makeMoney(100)
        )

        let missingPolicyAdvice = TransferPolicyEvaluator.evaluate(
            try makeMoney(100),
            cachedPolicy: nil
        )

        XCTAssertEqual(missingPolicyAdvice, .unavailable)

        let cases: [(Int64, TransferPolicyAdvice)] = [
            (99, .withinCachedLimit),
            (100, .withinCachedLimit),
            (101, .exceedsCachedLimit),
        ]

        for (minorUnits, expectedAdvice) in cases {
            let advice = TransferPolicyEvaluator.evaluate(
                try makeMoney(minorUnits),
                cachedPolicy: policy
            )

            XCTAssertEqual(advice, expectedAdvice)
        }
    }

    func test_backendDecision_overridesCachedAdvice() async throws {
        let policy = TransferLimitPolicy(
            maximumPerTransfer: try makeMoney(100)
        )
        let cases: [
            (
                Int64,
                TransferPolicyAdvice,
                TransferSubmissionResult,
                TransferState
            )
        ] = [
            (101, .exceedsCachedLimit, .accepted, .accepted),
            (99, .withinCachedLimit, .rejected, .rejected),
        ]

        for (minorUnits, expectedAdvice, backendResult, expectedState) in cases {
            let intent = try makeIntent(minorUnits)
            let advice = TransferPolicyEvaluator.evaluate(
                intent.amount,
                cachedPolicy: policy
            )
            let gateway = PolicyGatewaySpy(
                result: .success(backendResult)
            )
            let coordinator = TransferCoordinator(
                journal: PolicyJournalFake(),
                gateway: gateway
            )

            let state = try await coordinator.submit(intent)
            let failure = await coordinator.failure(for: intent.id)
            let callCount = await gateway.callCount

            XCTAssertEqual(advice, expectedAdvice)
            XCTAssertEqual(state, expectedState)
            XCTAssertNil(failure)
            XCTAssertEqual(callCount, 1)
        }
    }

    func test_submissionFailures_preserveCauseWithoutFinancialRejection() async throws {
        let cases: [
            (any Error, TransferFailure, TransferFailureAction)
        ] = [
            (
                TransferFailure.authenticationRequired,
                .authenticationRequired,
                .signIn
            ),
            (
                TransferFailure.stepUpRequired,
                .stepUpRequired,
                .authenticate
            ),
            (
                TransferFailure.transportFailure,
                .transportFailure,
                .reconcile
            ),
            (
                CancellationError(),
                .cancelled,
                .reconcile
            ),
        ]

        for (error, expectedFailure, expectedAction) in cases {
            let intent = try makeIntent()
            let journal = PolicyJournalFake()
            let gateway = PolicyGatewaySpy(result: .failure(error))
            let coordinator = TransferCoordinator(
                journal: journal,
                gateway: gateway
            )

            let state = try await coordinator.submit(intent)
            let failure = await coordinator.failure(for: intent.id)
            let persisted = try await journal.entry(for: intent.id)

            let repeatedState = try await coordinator.submit(intent)
            let repeatedFailure = await coordinator.failure(for: intent.id)
            let callCount = await gateway.callCount

            XCTAssertEqual(state, .unknown)
            XCTAssertEqual(failure, expectedFailure)
            XCTAssertEqual(failure?.suggestedAction, expectedAction)
            XCTAssertEqual(persisted?.intent, intent)

            XCTAssertEqual(repeatedState, .unknown)
            XCTAssertEqual(repeatedFailure, expectedFailure)
            XCTAssertEqual(callCount, 1)
        }
    }

    func test_unclassifiedGatewayError_requiresReconciliation() async throws {
        let intent = try makeIntent()
        let coordinator = TransferCoordinator(
            journal: PolicyJournalFake(),
            gateway: PolicyGatewaySpy(
                result: .failure(UnclassifiedGatewayError())
            )
        )

        let state = try await coordinator.submit(intent)
        let failure = await coordinator.failure(for: intent.id)

        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(failure, .unknownOutcome)
        XCTAssertEqual(failure?.suggestedAction, .reconcile)
    }

    func test_existingJournalEntry_requiresReconciliationWithoutSubmission() async throws {
        let intent = try makeIntent()
        let existing = JournaledTransfer(
            intent: intent,
            idempotencyKey: UUID()
        )
        let gateway = PolicyGatewaySpy(result: .success(.accepted))
        let coordinator = TransferCoordinator(
            journal: PolicyJournalFake(existing: existing),
            gateway: gateway
        )

        let state = try await coordinator.submit(intent)
        let failure = await coordinator.failure(for: intent.id)
        let callCount = await gateway.callCount

        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(failure, .unknownOutcome)
        XCTAssertEqual(failure?.suggestedAction, .reconcile)
        XCTAssertEqual(callCount, 0)
    }

    private func makeMoney(_ minorUnits: Int64) throws -> Money {
        try Money(
            minorUnits: minorUnits,
            currencyCode: "IDR",
            scale: 2
        )
    }

    private func makeIntent(
        _ minorUnits: Int64 = 100
    ) throws -> TransferIntent {
        TransferIntent(
            id: UUID(),
            amount: try makeMoney(minorUnits)
        )
    }
}

private struct UnclassifiedGatewayError: Error {}

private actor PolicyGatewaySpy: TransferGateway {
    private let result: Result<TransferSubmissionResult, any Error>
    private(set) var callCount = 0

    init(result: Result<TransferSubmissionResult, any Error>) {
        self.result = result
    }

    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        callCount += 1
        return try result.get()
    }
}

private actor PolicyJournalFake: TransferJournal {
    private var entries: [UUID: JournaledTransfer] = [:]

    init(existing: JournaledTransfer? = nil) {
        if let existing {
            entries[existing.intent.id] = existing
        }
    }

    func record(
        _ intent: TransferIntent,
        idempotencyKey: UUID
    ) async throws -> JournaledTransfer {
        if let existing = entries[intent.id] {
            guard existing.intent == intent else {
                throw TransferJournalError.intentConflict
            }

            return existing
        }

        guard !entries.values.contains(
            where: { $0.idempotencyKey == idempotencyKey }
        ) else {
            throw TransferJournalError.idempotencyKeyConflict
        }

        let entry = JournaledTransfer(
            intent: intent,
            idempotencyKey: idempotencyKey
        )
        entries[intent.id] = entry
        return entry
    }

    func entry(for intentID: UUID) async throws -> JournaledTransfer? {
        entries[intentID]
    }
}
