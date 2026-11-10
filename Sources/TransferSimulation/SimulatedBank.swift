//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore

/// A stateful, in-process gateway for tests and demos only.
///
/// Separate instances can share one store to model independent clients
/// reaching the same simulated uniqueness boundary.
public actor SimulatedBank: TransferGateway, TransferStatusGateway {
    private let store: SimulatedTransferStore
    private var faults: [UUID: SimulatedBankFault]

    public init(
        store: SimulatedTransferStore = SimulatedTransferStore(),
        faults: [UUID: SimulatedBankFault] = [:]
    ) {
        self.store = store
        self.faults = faults
    }

    public func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        // Reserve the one-shot fault before suspension.
        // A conflicting attempt consumes its configured fault but still
        // throws the store conflict before response fault delivery.
        let fault = faults.removeValue(forKey: transfer.idempotencyKey)

        let result = try await store.accept(transfer)

        switch fault {
        case .some(.timeoutAfterCommit):
            throw SimulatedBankError.timedOut

        case let .some(.delayedResponse(wait)):
            await wait()

        case .none:
            break
        }

        return result
    }

    public func status(
        for intentID: UUID,
        idempotencyKey: UUID
    ) async throws -> TransferStatusResponse {
        try await store.status(
            for: intentID,
            idempotencyKey: idempotencyKey
        )
    }
}
