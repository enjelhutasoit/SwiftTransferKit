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
final class SimulatedBankTests: XCTestCase {
    func testConcurrentReplayAcrossGatewaysCreatesOneAcceptedTransfer() async throws {
        let transfer = try makeTransfer()
        let store = SimulatedTransferStore()
        let firstBank = SimulatedBank(store: store)
        let secondBank = SimulatedBank(store: store)

        async let first = firstBank.submit(transfer)
        async let second = secondBank.submit(transfer)

        let (firstResult, secondResult) = try await (first, second)
        let replayResult = try await secondBank.submit(transfer)
        let count = await store.acceptedTransferCount
        let stored = await store.acceptedTransfer(
            for: transfer.idempotencyKey
        )

        XCTAssertEqual(firstResult, .accepted)
        XCTAssertEqual(secondResult, .accepted)
        XCTAssertEqual(replayResult, .accepted)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(stored, transfer)
    }

    func testTimeoutAfterCommitPreservesAcceptedTransferAndReplay() async throws {
        let transfer = try makeTransfer()
        let store = SimulatedTransferStore()
        let bank = SimulatedBank(
            store: store,
            faults: [
                transfer.idempotencyKey: .timeoutAfterCommit
            ]
        )

        await assertBankError(
            .timedOut,
            bank: bank,
            transfer: transfer
        )

        let storedAfterTimeout = await store.acceptedTransfer(
            for: transfer.idempotencyKey
        )
        let countAfterTimeout = await store.acceptedTransferCount

        XCTAssertEqual(storedAfterTimeout, transfer)
        XCTAssertEqual(countAfterTimeout, 1)

        let replayResult = try await bank.submit(transfer)
        let countAfterReplay = await store.acceptedTransferCount

        XCTAssertEqual(replayResult, .accepted)
        XCTAssertEqual(countAfterReplay, 1)
    }

    func testSameKeyWithDifferentPayloadIsRejected() async throws {
        let original = try makeTransfer()
        let changedAmount = try makeTransfer(minorUnits: 250_000)
        let changedIdentity = try makeTransfer(
            intentID: "33333333-3333-3333-3333-333333333333"
        )
        let store = SimulatedTransferStore()
        let bank = SimulatedBank(store: store)

        _ = try await bank.submit(original)

        for conflictingTransfer in [changedAmount, changedIdentity] {
            await assertBankError(
                .idempotencyKeyConflict,
                bank: bank,
                transfer: conflictingTransfer
            )
        }

        let count = await store.acceptedTransferCount
        let preserved = await store.acceptedTransfer(
            for: original.idempotencyKey
        )

        XCTAssertEqual(count, 1)
        XCTAssertEqual(preserved, original)
    }

    func testSameIntentWithDifferentKeyIsRejected() async throws {
        let original = try makeTransfer()
        let changedKey = try makeTransfer(
            idempotencyKey: "44444444-4444-4444-4444-444444444444"
        )
        let store = SimulatedTransferStore()
        let bank = SimulatedBank(store: store)

        _ = try await bank.submit(original)

        await assertBankError(
            .intentConflict,
            bank: bank,
            transfer: changedKey
        )

        let count = await store.acceptedTransferCount
        let originalEntry = await store.acceptedTransfer(
            for: original.idempotencyKey
        )
        let additionalEntry = await store.acceptedTransfer(
            for: changedKey.idempotencyKey
        )

        XCTAssertEqual(count, 1)
        XCTAssertEqual(originalEntry, original)
        XCTAssertNil(additionalEntry)
    }

    func testDelayedResponseAllowsReplayWithoutAnotherTransfer() async throws {
        let transfer = try makeTransfer()
        let store = SimulatedTransferStore()
        let gate = ResponseGate()
        let delayedBank = SimulatedBank(
            store: store,
            faults: [
                transfer.idempotencyKey: .delayedResponse {
                    await gate.wait()
                }
            ]
        )
        let replayBank = SimulatedBank(store: store)

        addTeardownBlock {
            await gate.open()
        }

        let delayedSubmission = Task {
            try await delayedBank.submit(transfer)
        }

        await gate.waitUntilEntered()

        let storedBeforeResponse = await store.acceptedTransfer(
            for: transfer.idempotencyKey
        )
        let replayResult = try await replayBank.submit(transfer)
        let countBeforeResponse = await store.acceptedTransferCount

        XCTAssertEqual(storedBeforeResponse, transfer)
        XCTAssertEqual(replayResult, .accepted)
        XCTAssertEqual(countBeforeResponse, 1)

        await gate.open()

        let delayedResult = try await delayedSubmission.value
        let finalCount = await store.acceptedTransferCount

        XCTAssertEqual(delayedResult, .accepted)
        XCTAssertEqual(finalCount, 1)
    }

    func testCoordinatorRemainsUnknownAfterBankCommitsAndResponseIsLost() async throws {
        let transfer = try makeTransfer()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SimulatedBankTests-\(UUID().uuidString)",
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

        let firstState = try await coordinator.submit(transfer.intent)
        let repeatedState = try await coordinator.submit(transfer.intent)
        let journaled = try await journal.entry(for: transfer.intent.id)
        let accepted = await store.acceptedTransfer(
            for: transfer.idempotencyKey
        )
        let count = await store.acceptedTransferCount

        XCTAssertEqual(firstState, .unknown)
        XCTAssertEqual(repeatedState, .unknown)
        XCTAssertEqual(journaled, transfer)
        XCTAssertEqual(accepted, transfer)
        XCTAssertEqual(count, 1)
    }

    private func makeTransfer(
        minorUnits: Int64 = 125_000,
        intentID: String = "11111111-1111-1111-1111-111111111111",
        idempotencyKey: String = "22222222-2222-2222-2222-222222222222"
    ) throws -> JournaledTransfer {
        let id = try XCTUnwrap(UUID(uuidString: intentID))
        let key = try XCTUnwrap(UUID(uuidString: idempotencyKey))
        let amount = try Money(
            minorUnits: minorUnits,
            currencyCode: "IDR",
            scale: 2
        )

        return JournaledTransfer(
            intent: TransferIntent(id: id, amount: amount),
            idempotencyKey: key
        )
    }

    private func assertBankError(
        _ expected: SimulatedBankError,
        bank: SimulatedBank,
        transfer: JournaledTransfer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await bank.submit(transfer)
            XCTFail("Expected submission to throw.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? SimulatedBankError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private actor ResponseGate {
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
