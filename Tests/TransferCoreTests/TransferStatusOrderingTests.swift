//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferSimulation
import XCTest

@MainActor
final class TransferStatusOrderingTests: XCTestCase {
    func testOlderAndDuplicateResponsesPreserveLatestSnapshot() async throws {
        let transfer = try makeTransfer()
        let gateway = OrderingGatewayStub(
            steps: [
                .response(response(transfer, status: .settled, version: 3)),
                .response(response(transfer, status: .accepted, version: 2)),
                .response(response(transfer, status: .settled, version: 3)),
            ]
        )
        let service = try makeService(transfer, gateway: gateway)

        for _ in 0..<3 {
            let result = try await service.reconcile(
                intentID: transfer.intent.id
            )

            XCTAssertEqual(
                result,
                .confirmed(state: .settled, attempts: 1)
            )
        }

        let latest = await service.latestStatus(for: transfer.intent.id)

        XCTAssertEqual(
            latest,
            snapshot(.settled, version: 3)
        )
    }

    func testSameVersionConflictDoesNotReplaceSnapshot() async throws {
        let transfer = try makeTransfer()
        let gateway = OrderingGatewayStub(
            steps: [
                .response(response(transfer, status: .accepted, version: 2)),
                .response(response(transfer, status: .rejected, version: 2)),
            ]
        )
        let service = try makeService(transfer, gateway: gateway)

        _ = try await service.reconcile(intentID: transfer.intent.id)

        do {
            _ = try await service.reconcile(intentID: transfer.intent.id)
            XCTFail("Expected a same-version conflict.")
        } catch {
            XCTAssertEqual(
                error as? TransferStateMachine.StatusUpdateError,
                .conflictingVersion(TransferStatusVersion(rawValue: 2))
            )
        }

        let latest = await service.latestStatus(for: transfer.intent.id)
        XCTAssertEqual(latest, snapshot(.accepted, version: 2))
    }

    func testHigherVersionCannotRewriteSettledAsRejected() async throws {
        let transfer = try makeTransfer()
        let gateway = OrderingGatewayStub(
            steps: [
                .response(response(transfer, status: .settled, version: 2)),
                .response(response(transfer, status: .rejected, version: 3)),
            ]
        )
        let service = try makeService(transfer, gateway: gateway)

        _ = try await service.reconcile(intentID: transfer.intent.id)

        do {
            _ = try await service.reconcile(intentID: transfer.intent.id)
            XCTFail("Expected an invalid lifecycle transition.")
        } catch {
            XCTAssertEqual(
                error as? TransferStateMachine.TransitionError,
                .invalidTransition(
                    state: .settled,
                    event: .serverRejected
                )
            )
        }

        let latest = await service.latestStatus(for: transfer.intent.id)
        XCTAssertEqual(latest, snapshot(.settled, version: 2))
    }

    func testDelayedOlderResponseCannotReplaceNewerResponse() async throws {
        let transfer = try makeTransfer()
        let gate = StatusResponseGate()
        let gateway = OrderingGatewayStub(
            steps: [
                .delayed(
                    response(transfer, status: .accepted, version: 1),
                    gate
                ),
                .response(response(transfer, status: .settled, version: 2)),
            ]
        )
        let service = try makeService(transfer, gateway: gateway)

        addTeardownBlock {
            await gate.open()
        }

        let olderRequest = Task {
            try await service.reconcile(intentID: transfer.intent.id)
        }

        await gate.waitUntilEntered()

        let newerResult = try await service.reconcile(
            intentID: transfer.intent.id
        )

        await gate.open()

        let olderResult = try await olderRequest.value
        let latest = await service.latestStatus(for: transfer.intent.id)

        XCTAssertEqual(
            newerResult,
            .confirmed(state: .settled, attempts: 1)
        )
        XCTAssertEqual(
            olderResult,
            .confirmed(state: .settled, attempts: 1)
        )
        XCTAssertEqual(latest, snapshot(.settled, version: 2))
    }

    func testMissingVersionCannotReplaceVersionedSnapshot() async throws {
        let transfer = try makeTransfer()
        let gateway = OrderingGatewayStub(
            steps: [
                .response(response(transfer, status: .accepted, version: 1)),
                .response(response(transfer, status: .settled, version: nil)),
            ]
        )
        let service = try makeService(transfer, gateway: gateway)

        _ = try await service.reconcile(intentID: transfer.intent.id)

        do {
            _ = try await service.reconcile(intentID: transfer.intent.id)
            XCTFail("Expected a missing-version error.")
        } catch {
            XCTAssertEqual(
                error as? TransferStateMachine.StatusUpdateError,
                .missingVersion
            )
        }

        let latest = await service.latestStatus(for: transfer.intent.id)
        XCTAssertEqual(latest, snapshot(.accepted, version: 1))
    }

    func testOutagePreservesPreviouslyConfirmedSnapshot() async throws {
        let transfer = try makeTransfer()
        let gateway = OrderingGatewayStub(
            steps: [
                .response(response(transfer, status: .accepted, version: 2)),
                .unavailable,
            ]
        )
        let service = try makeService(transfer, gateway: gateway)

        _ = try await service.reconcile(intentID: transfer.intent.id)
        let result = try await service.reconcile(
            intentID: transfer.intent.id
        )
        let latest = await service.latestStatus(for: transfer.intent.id)

        XCTAssertEqual(result, .unresolved(attempts: 1))
        XCTAssertEqual(latest, snapshot(.accepted, version: 2))
    }

    func testSimulatorVersionsAreSharedAndReplayDoesNotIncrementThem() async throws {
        let transfer = try makeTransfer()
        let store = SimulatedTransferStore()
        let firstBank = SimulatedBank(store: store)
        let secondBank = SimulatedBank(store: store)

        _ = try await firstBank.submit(transfer)

        let firstStatus = try await firstBank.status(
            for: transfer.intent.id,
            idempotencyKey: transfer.idempotencyKey
        )

        _ = try await secondBank.submit(transfer)

        let replayStatus = try await secondBank.status(
            for: transfer.intent.id,
            idempotencyKey: transfer.idempotencyKey
        )

        let advanced = try await store.advanceStatus(
            for: transfer.idempotencyKey,
            to: .settled
        )
        let finalStatus = try await firstBank.status(
            for: transfer.intent.id,
            idempotencyKey: transfer.idempotencyKey
        )
        let count = await store.acceptedTransferCount

        XCTAssertEqual(firstStatus.status, .accepted)
        XCTAssertEqual(
            firstStatus.version,
            TransferStatusVersion(rawValue: 1)
        )
        XCTAssertEqual(replayStatus, firstStatus)
        XCTAssertEqual(advanced, snapshot(.settled, version: 2))
        XCTAssertEqual(finalStatus.status, .settled)
        XCTAssertEqual(
            finalStatus.version,
            TransferStatusVersion(rawValue: 2)
        )
        XCTAssertEqual(count, 1)
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
        _ transfer: JournaledTransfer,
        status: TransferStatusResponse.Status,
        version: UInt64?
    ) -> TransferStatusResponse {
        TransferStatusResponse(
            intentID: transfer.intent.id,
            idempotencyKey: transfer.idempotencyKey,
            status: status,
            version: version.map { TransferStatusVersion(rawValue: $0) }
        )
    }

    private func snapshot(
        _ state: TransferState,
        version: UInt64
    ) -> TransferStatusSnapshot {
        TransferStatusSnapshot(
            state: state,
            version: TransferStatusVersion(rawValue: version)
        )
    }

    private func makeService(
        _ transfer: JournaledTransfer,
        gateway: any TransferStatusGateway
    ) throws -> TransferReconciliationService {
        TransferReconciliationService(
            journal: OrderingJournalStub(entry: transfer),
            gateway: gateway,
            policy: try ReconciliationPolicy(maximumAttempts: 1),
            sleep: { _ in }
        )
    }
}

private struct OrderingJournalStub: TransferJournal {
    let entry: JournaledTransfer

    func entry(for intentID: UUID) async throws -> JournaledTransfer? {
        entry.intent.id == intentID ? entry : nil
    }

    func record(
        _ intent: TransferIntent,
        idempotencyKey: UUID
    ) async throws -> JournaledTransfer {
        throw TransferJournalError.storageFailure
    }
}

private enum OrderingStep: Sendable {
    case response(TransferStatusResponse)
    case delayed(TransferStatusResponse, StatusResponseGate)
    case unavailable
}

private enum OrderingGatewayError: Error {
    case unavailable
}

private actor OrderingGatewayStub: TransferStatusGateway {
    private var steps: [OrderingStep]

    init(steps: [OrderingStep]) {
        self.steps = steps
    }

    func status(
        for intentID: UUID,
        idempotencyKey: UUID
    ) async throws -> TransferStatusResponse {
        guard !steps.isEmpty else {
            throw OrderingGatewayError.unavailable
        }

        // Reserve the response before suspension.
        let step = steps.removeFirst()

        switch step {
        case let .response(response):
            return response

        case let .delayed(response, gate):
            await gate.wait()
            return response

        case .unavailable:
            throw OrderingGatewayError.unavailable
        }
    }
}

private actor StatusResponseGate {
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
