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
final class TransferRecoveryTests: XCTestCase {
    func testReopenedJournalRecoversBothCrashWindowsWithoutResubmitting() async throws {
        let transfer = try makeTransfer()

        for wasSubmitted in [false, true] {
            let storeURL = try makeStoreURL()
            try await persist([transfer], at: storeURL)

            let bankStore = SimulatedTransferStore()
            let bank = SimulatedBank(
                store: bankStore,
                faults: [
                    transfer.idempotencyKey: .timeoutAfterCommit
                ]
            )

            if wasSubmitted {
                do {
                    _ = try await bank.submit(transfer)
                    XCTFail("Expected the simulated response to be lost.")
                } catch {
                    XCTAssertEqual(
                        error as? SimulatedBankError,
                        .timedOut
                    )
                }
            }

            let reopenedJournal = try CoreDataTransferJournal(
                storeURL: storeURL
            )
            let recovery = try makeRecovery(
                journal: reopenedJournal,
                gateway: bank
            )

            let candidates = try await recovery.recover()
            let candidate = try XCTUnwrap(candidates.first)
            let preserved = try await reopenedJournal.entry(
                for: transfer.intent.id
            )
            let acceptedCount = await bankStore.acceptedTransferCount

            let expectedResult: ReconciliationResult = wasSubmitted
                ? .confirmed(state: .accepted, attempts: 1)
                : .unresolved(attempts: 1)

            let expectedClassification: RecoveryCandidate.Classification =
                wasSubmitted ? .processing : .unresolved

            XCTAssertEqual(candidates.count, 1)
            XCTAssertEqual(candidate.entry, transfer)
            XCTAssertEqual(candidate.reconciliation, expectedResult)
            XCTAssertEqual(candidate.classification, expectedClassification)
            XCTAssertEqual(preserved, transfer)
            XCTAssertEqual(acceptedCount, wasSubmitted ? 1 : 0)
        }
    }

    func testCompletedTransfersAreClassifiedWithoutSubmission() async throws {
        let settledTransfer = try makeTransfer()
        let rejectedTransfer = try makeTransfer(
            intentID: "33333333-3333-3333-3333-333333333333",
            idempotencyKey: "44444444-4444-4444-4444-444444444444"
        )
        let storeURL = try makeStoreURL()
        try await persist(
            [settledTransfer, rejectedTransfer],
            at: storeURL
        )

        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let gateway = RecoveryGatewaySpy(
            statuses: [
                settledTransfer.intent.id: .settled,
                rejectedTransfer.intent.id: .rejected,
            ]
        )
        let recovery = try makeRecovery(
            journal: journal,
            gateway: gateway
        )

        let candidates = try await recovery.recover()
        let submissionCount = await gateway.submissionCount

        let settled = try XCTUnwrap(
            candidates.first { $0.id == settledTransfer.intent.id }
        )
        let rejected = try XCTUnwrap(
            candidates.first { $0.id == rejectedTransfer.intent.id }
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(settled.classification, .completed)
        XCTAssertEqual(rejected.classification, .completed)
        XCTAssertEqual(
            settled.reconciliation,
            .confirmed(state: .settled, attempts: 1)
        )
        XCTAssertEqual(
            rejected.reconciliation,
            .confirmed(state: .rejected, attempts: 1)
        )
        XCTAssertEqual(submissionCount, 0)
    }

    func testStatusOutagePreservesJournalForAnotherRecovery() async throws {
        let first = try makeTransfer()
        let second = try makeTransfer(
            intentID: "33333333-3333-3333-3333-333333333333",
            idempotencyKey: "44444444-4444-4444-4444-444444444444"
        )
        let storeURL = try makeStoreURL()
        try await persist([first, second], at: storeURL)

        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let gateway = RecoveryGatewaySpy(isUnavailable: true)
        let recovery = try makeRecovery(
            journal: journal,
            gateway: gateway
        )

        let candidates = try await recovery.recover()

        let reopenedJournal = try CoreDataTransferJournal(
            storeURL: storeURL
        )
        let preserved = try await reopenedJournal.allEntries()
        let queryCount = await gateway.queryCount
        let submissionCount = await gateway.submissionCount

        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(
            candidates.allSatisfy {
                $0.classification == .unresolved
                    && $0.reconciliation == .unresolved(attempts: 1)
            }
        )
        XCTAssertEqual(preserved, [first, second])
        XCTAssertEqual(queryCount, 2)
        XCTAssertEqual(submissionCount, 0)
    }

    func testScanFailurePreventsQueriesAndAllowsLaterRecovery() async throws {
        let transfer = try makeTransfer()
        let journal = RecoveryJournalStub(
            entries: [transfer],
            failsScan: true
        )
        let gateway = RecoveryGatewaySpy(
            statuses: [transfer.intent.id: .accepted]
        )
        let recovery = try makeRecovery(
            journal: journal,
            gateway: gateway
        )

        await assertRecoveryError(
            .journalUnavailable,
            recovery: recovery
        )

        let queriesAfterFailure = await gateway.queryCount
        XCTAssertEqual(queriesAfterFailure, 0)

        await journal.setScanFailure(false)

        let candidates = try await recovery.recover()
        let queriesAfterRetry = await gateway.queryCount
        let recordCalls = await journal.recordCalls

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.classification, .processing)
        XCTAssertEqual(queriesAfterRetry, 1)
        XCTAssertEqual(recordCalls, 0)
    }

    func testConcurrentRecoveryDoesNotStartAnotherPass() async throws {
        let transfer = try makeTransfer()
        let journal = RecoveryJournalStub(entries: [transfer])
        let gate = RecoveryQueryGate()
        let gateway = RecoveryGatewaySpy(
            statuses: [transfer.intent.id: .accepted],
            gate: gate
        )
        let recovery = try makeRecovery(
            journal: journal,
            gateway: gateway
        )

        addTeardownBlock {
            await gate.open()
        }

        let firstPass = Task {
            try await recovery.recover()
        }

        await gate.waitUntilEntered()

        await assertRecoveryError(
            .recoveryInProgress,
            recovery: recovery
        )

        await gate.open()

        let candidates = try await firstPass.value
        let queryCount = await gateway.queryCount

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(queryCount, 1)
    }

    func testCancellationReleasesRecoveryReservation() async throws {
        let transfer = try makeTransfer()
        let journal = RecoveryJournalStub(entries: [transfer])
        let gateway = RecoveryGatewaySpy(
            statuses: [transfer.intent.id: .accepted],
            cancelsNextQuery: true
        )
        let recovery = try makeRecovery(
            journal: journal,
            gateway: gateway
        )

        do {
            _ = try await recovery.recover()
            XCTFail("Expected cancellation.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let candidates = try await recovery.recover()
        let queryCount = await gateway.queryCount

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.classification, .processing)
        XCTAssertEqual(queryCount, 2)
    }

    private func makeTransfer(
        intentID: String = "11111111-1111-1111-1111-111111111111",
        idempotencyKey: String = "22222222-2222-2222-2222-222222222222"
    ) throws -> JournaledTransfer {
        let id = try XCTUnwrap(UUID(uuidString: intentID))
        let key = try XCTUnwrap(UUID(uuidString: idempotencyKey))
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

    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TransferRecoveryTests-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }

        return directory.appendingPathComponent("journal.sqlite")
    }

    private func persist(
        _ entries: [JournaledTransfer],
        at storeURL: URL
    ) async throws {
        let writer = try CoreDataTransferJournal(storeURL: storeURL)

        for entry in entries {
            _ = try await writer.record(
                entry.intent,
                idempotencyKey: entry.idempotencyKey
            )
        }
    }

    private func makeRecovery(
        journal: any TransferRecoveryJournal,
        gateway: any TransferStatusGateway
    ) throws -> TransferRecoveryService {
        TransferRecoveryService(
            journal: journal,
            gateway: gateway,
            policy: try ReconciliationPolicy(maximumAttempts: 1),
            sleep: { _ in }
        )
    }

    private func assertRecoveryError(
        _ expected: TransferRecoveryService.Failure,
        recovery: TransferRecoveryService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await recovery.recover()
            XCTFail("Expected recovery to throw.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? TransferRecoveryService.Failure,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private actor RecoveryJournalStub: TransferRecoveryJournal {
    private let entries: [JournaledTransfer]
    private var failsScan: Bool

    private(set) var recordCalls = 0

    init(entries: [JournaledTransfer], failsScan: Bool = false) {
        self.entries = entries
        self.failsScan = failsScan
    }

    func allEntries() async throws -> [JournaledTransfer] {
        if failsScan {
            throw TransferJournalError.storageFailure
        }

        return entries
    }

    func entry(for intentID: UUID) async throws -> JournaledTransfer? {
        entries.first { $0.intent.id == intentID }
    }

    func record(
        _ intent: TransferIntent,
        idempotencyKey: UUID
    ) async throws -> JournaledTransfer {
        recordCalls += 1
        throw TransferJournalError.storageFailure
    }

    func setScanFailure(_ value: Bool) {
        failsScan = value
    }
}

private enum RecoveryGatewayError: Error {
    case unavailable
    case unexpectedSubmission
}

private actor RecoveryGatewaySpy: TransferStatusGateway, TransferGateway {
    private let statuses: [UUID: TransferStatusResponse.Status]
    private let isUnavailable: Bool
    private let gate: RecoveryQueryGate?
    private var cancelsNextQuery: Bool

    private(set) var queryCount = 0
    private(set) var submissionCount = 0

    init(
        statuses: [UUID: TransferStatusResponse.Status] = [:],
        isUnavailable: Bool = false,
        cancelsNextQuery: Bool = false,
        gate: RecoveryQueryGate? = nil
    ) {
        self.statuses = statuses
        self.isUnavailable = isUnavailable
        self.cancelsNextQuery = cancelsNextQuery
        self.gate = gate
    }

    func status(
        for intentID: UUID,
        idempotencyKey: UUID
    ) async throws -> TransferStatusResponse {
        queryCount += 1

        if cancelsNextQuery {
            cancelsNextQuery = false
            throw CancellationError()
        }

        if isUnavailable {
            throw RecoveryGatewayError.unavailable
        }

        if let gate {
            await gate.wait()
        }

        return TransferStatusResponse(
            intentID: intentID,
            idempotencyKey: idempotencyKey,
            status: statuses[intentID] ?? .notFound
        )
    }

    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        submissionCount += 1
        throw RecoveryGatewayError.unexpectedSubmission
    }
}

private actor RecoveryQueryGate {
    private var isOpen = false
    private var hasEntered = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        hasEntered = true

        let pendingObservers = observers
        observers.removeAll()

        for observer in pendingObservers {
            observer.resume()
        }

        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            blocked.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else {
            return
        }

        await withCheckedContinuation { continuation in
            observers.append(continuation)
        }
    }

    func open() {
        isOpen = true

        let pending = blocked
        blocked.removeAll()

        for continuation in pending {
            continuation.resume()
        }
    }
}
