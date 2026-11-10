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
final class TransferReconciliationTests: XCTestCase {
    func testTimeoutAfterCommitResolvesWithoutAnotherTransfer() async throws {
        let transfer = try makeTransfer()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReconciliationTests-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }

        let journal = try CoreDataTransferJournal(
            storeURL: directory.appendingPathComponent("journal.sqlite")
        )
        let store = SimulatedTransferStore()
        let bank = SimulatedBank(
            store: store,
            faults: [
                transfer.idempotencyKey: .timeoutAfterCommit
            ]
        )
        let coordinator = TransferCoordinator(
            journal: journal,
            gateway: bank,
            makeIdempotencyKey: { transfer.idempotencyKey }
        )

        let submissionState = try await coordinator.submit(transfer.intent)
        let entryBeforeQuery = try await journal.entry(
            for: transfer.intent.id
        )
        let service = try makeService(journal: journal, gateway: bank)

        let result = try await service.reconcile(
            intentID: transfer.intent.id
        )

        let entryAfterQuery = try await journal.entry(
            for: transfer.intent.id
        )
        let acceptedCount = await store.acceptedTransferCount

        XCTAssertEqual(submissionState, .unknown)
        XCTAssertEqual(
            result,
            .confirmed(state: .accepted, attempts: 1)
        )
        XCTAssertEqual(entryBeforeQuery, transfer)
        XCTAssertEqual(entryAfterQuery, entryBeforeQuery)
        XCTAssertEqual(acceptedCount, 1)
    }

    func testUnresolvedResponsesRespectAttemptLimitAndPreserveIdentity() async throws {
        let transfer = try makeTransfer()
        let unresolvedSteps: [StatusStep] = [
            .response(response(for: transfer, status: .pending)),
            .response(response(for: transfer, status: .notFound)),
            .unavailable,
        ]

        for step in unresolvedSteps {
            let journal = ReconciliationJournalSpy(entry: transfer)
            let gateway = ScriptedStatusGateway(
                steps: Array(repeating: step, count: 3)
            )
            let sleeper = RetrySleepSpy()
            let service = try makeService(
                journal: journal,
                gateway: gateway,
                sleeper: sleeper
            )

            let result = try await service.reconcile(
                intentID: transfer.intent.id
            )

            let queries = await gateway.queries
            let delays = await sleeper.delays
            let recordCalls = await journal.recordCalls
            let preservedEntry = try await journal.entry(
                for: transfer.intent.id
            )

            XCTAssertEqual(result, .unresolved(attempts: 3))
            XCTAssertEqual(
                queries,
                Array(
                    repeating: StatusQuery(
                        intentID: transfer.intent.id,
                        idempotencyKey: transfer.idempotencyKey
                    ),
                    count: 3
                )
            )
            XCTAssertEqual(delays, [7, 7])
            XCTAssertEqual(recordCalls, 0)
            XCTAssertEqual(preservedEntry, transfer)
        }
    }

    func testTransientOutageCanResolveWithinAttemptLimit() async throws {
        let transfer = try makeTransfer()
        let journal = ReconciliationJournalSpy(entry: transfer)
        let gateway = ScriptedStatusGateway(
            steps: [
                .unavailable,
                .response(response(for: transfer, status: .pending)),
                .response(response(for: transfer, status: .accepted)),
            ]
        )
        let sleeper = RetrySleepSpy()
        let service = try makeService(
            journal: journal,
            gateway: gateway,
            sleeper: sleeper
        )

        let result = try await service.reconcile(
            intentID: transfer.intent.id
        )
        let queryCount = await gateway.queries.count
        let delays = await sleeper.delays

        XCTAssertEqual(
            result,
            .confirmed(state: .accepted, attempts: 3)
        )
        XCTAssertEqual(queryCount, 3)
        XCTAssertEqual(delays, [7, 7])
    }

    func testTerminalStatusesStopFurtherQueries() async throws {
        let transfer = try makeTransfer()
        let cases: [(TransferStatusResponse.Status, TransferState)] = [
            (.settled, .settled),
            (.rejected, .rejected),
        ]

        for (serverStatus, expectedState) in cases {
            let journal = ReconciliationJournalSpy(entry: transfer)
            let gateway = ScriptedStatusGateway(
                steps: [
                    .response(response(for: transfer, status: serverStatus))
                ]
            )
            let sleeper = RetrySleepSpy()
            let service = try makeService(
                journal: journal,
                gateway: gateway,
                sleeper: sleeper
            )

            let result = try await service.reconcile(
                intentID: transfer.intent.id
            )
            let queryCount = await gateway.queries.count
            let delays = await sleeper.delays

            XCTAssertEqual(
                result,
                .confirmed(state: expectedState, attempts: 1)
            )
            XCTAssertEqual(queryCount, 1)
            XCTAssertTrue(delays.isEmpty)
        }
    }

    func testMismatchedResponseIdentityCannotConfirmOutcome() async throws {
        let transfer = try makeTransfer()
        let otherID = try XCTUnwrap(
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")
        )
        let responses = [
            TransferStatusResponse(
                intentID: otherID,
                idempotencyKey: transfer.idempotencyKey,
                status: .settled
            ),
            TransferStatusResponse(
                intentID: transfer.intent.id,
                idempotencyKey: otherID,
                status: .settled
            ),
        ]

        for mismatchedResponse in responses {
            let journal = ReconciliationJournalSpy(entry: transfer)
            let gateway = ScriptedStatusGateway(
                steps: [.response(mismatchedResponse)]
            )
            let service = try makeService(
                journal: journal,
                gateway: gateway,
                maximumAttempts: 1
            )

            let result = try await service.reconcile(
                intentID: transfer.intent.id
            )

            XCTAssertEqual(result, .unresolved(attempts: 1))
        }
    }

    func testMissingOrUnreadableJournalPreventsStatusQuery() async throws {
        let transfer = try makeTransfer()
        let cases: [
            (
                ReconciliationJournalSpy,
                TransferReconciliationService.Failure
            )
        ] = [
            (
                ReconciliationJournalSpy(entry: nil),
                .intentNotFound
            ),
            (
                ReconciliationJournalSpy(
                    entry: transfer,
                    failsReads: true
                ),
                .persistenceFailure
            ),
        ]

        for (journal, expectedError) in cases {
            let gateway = ScriptedStatusGateway(steps: [])
            let service = try makeService(
                journal: journal,
                gateway: gateway
            )

            do {
                _ = try await service.reconcile(intentID: transfer.intent.id)
                XCTFail("Expected reconciliation to throw.")
            } catch {
                XCTAssertEqual(
                    error as? TransferReconciliationService.Failure,
                    expectedError
                )
            }

            let queries = await gateway.queries
            let recordCalls = await journal.recordCalls

            XCTAssertTrue(queries.isEmpty)
            XCTAssertEqual(recordCalls, 0)
        }
    }

    func testCancellationStopsWithoutRetrying() async throws {
        let transfer = try makeTransfer()
        let journal = ReconciliationJournalSpy(entry: transfer)
        let gateway = ScriptedStatusGateway(steps: [.cancelled])
        let sleeper = RetrySleepSpy()
        let service = try makeService(
            journal: journal,
            gateway: gateway,
            sleeper: sleeper
        )

        do {
            _ = try await service.reconcile(intentID: transfer.intent.id)
            XCTFail("Expected cancellation.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let queryCount = await gateway.queries.count
        let delays = await sleeper.delays

        XCTAssertEqual(queryCount, 1)
        XCTAssertTrue(delays.isEmpty)
    }

    func testPolicyRejectsAttemptCountsOutsideSupportedRange() {
        for count in [0, 6] {
            XCTAssertThrowsError(
                try ReconciliationPolicy(maximumAttempts: count)
            ) { error in
                XCTAssertEqual(
                    error as? ReconciliationPolicy.ValidationError,
                    .invalidMaximumAttempts
                )
            }
        }
    }

    private func makeTransfer() throws -> JournaledTransfer {
        let id = try XCTUnwrap(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let key = try XCTUnwrap(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let amount = try Money(
            minorUnits: 125_000,
            currencyCode: "IDR",
            scale: 2
        )

        return JournaledTransfer(
            intent: TransferIntent(id: id, amount: amount),
            idempotencyKey: key
        )
    }

    private func response(
        for transfer: JournaledTransfer,
        status: TransferStatusResponse.Status
    ) -> TransferStatusResponse {
        TransferStatusResponse(
            intentID: transfer.intent.id,
            idempotencyKey: transfer.idempotencyKey,
            status: status
        )
    }

    private func makeService(
        journal: any TransferJournal,
        gateway: any TransferStatusGateway,
        maximumAttempts: Int = 3,
        sleeper: RetrySleepSpy = RetrySleepSpy()
    ) throws -> TransferReconciliationService {
        TransferReconciliationService(
            journal: journal,
            gateway: gateway,
            policy: try ReconciliationPolicy(
                maximumAttempts: maximumAttempts,
                retryDelayNanoseconds: 7
            ),
            sleep: { duration in
                await sleeper.record(duration)
            }
        )
    }
}

private struct StatusQuery: Equatable, Sendable {
    let intentID: UUID
    let idempotencyKey: UUID
}

private enum StatusStep: Sendable {
    case response(TransferStatusResponse)
    case unavailable
    case cancelled
}

private enum StatusStubError: Error {
    case unavailable
}

private actor ScriptedStatusGateway: TransferStatusGateway {
    private var steps: [StatusStep]
    private(set) var queries: [StatusQuery] = []

    init(steps: [StatusStep]) {
        self.steps = steps
    }

    func status(
        for intentID: UUID,
        idempotencyKey: UUID
    ) async throws -> TransferStatusResponse {
        queries.append(
            StatusQuery(
                intentID: intentID,
                idempotencyKey: idempotencyKey
            )
        )

        guard !steps.isEmpty else {
            throw StatusStubError.unavailable
        }

        switch steps.removeFirst() {
        case let .response(response):
            return response

        case .unavailable:
            throw StatusStubError.unavailable

        case .cancelled:
            throw CancellationError()
        }
    }
}

private actor RetrySleepSpy {
    private(set) var delays: [UInt64] = []

    func record(_ duration: UInt64) {
        delays.append(duration)
    }
}

private actor ReconciliationJournalSpy: TransferJournal {
    private let storedEntry: JournaledTransfer?
    private let failsReads: Bool

    private(set) var recordCalls = 0

    init(entry: JournaledTransfer?, failsReads: Bool = false) {
        storedEntry = entry
        self.failsReads = failsReads
    }

    func entry(for intentID: UUID) async throws -> JournaledTransfer? {
        if failsReads {
            throw TransferJournalError.storageFailure
        }

        return storedEntry
    }

    func record(
        _ intent: TransferIntent,
        idempotencyKey: UUID
    ) async throws -> JournaledTransfer {
        recordCalls += 1
        throw TransferJournalError.storageFailure
    }
}
