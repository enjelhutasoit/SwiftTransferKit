//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore

/// In-memory acceptance storage for tests and demos.
///
/// This models a server-side uniqueness boundary within one process.
/// It does not persist data or model balances, debits, or settlement.
public actor SimulatedTransferStore {
    private var acceptedByKey: [UUID: JournaledTransfer] = [:]
    private var keysByIntent: [UUID: UUID] = [:]

    public init() {}

    public var acceptedTransferCount: Int {
        acceptedByKey.count
    }

    public func acceptedTransfer(
        for idempotencyKey: UUID
    ) -> JournaledTransfer? {
        acceptedByKey[idempotencyKey]
    }

    /// Checks uniqueness and records acceptance without a suspension point.
    func accept(
        _ transfer: JournaledTransfer
    ) throws -> TransferSubmissionResult {
        if let existing = acceptedByKey[transfer.idempotencyKey] {
            guard existing == transfer else {
                throw SimulatedBankError.idempotencyKeyConflict
            }

            return .accepted
        }

        guard keysByIntent[transfer.intent.id] == nil else {
            throw SimulatedBankError.intentConflict
        }

        acceptedByKey[transfer.idempotencyKey] = transfer
        keysByIntent[transfer.intent.id] = transfer.idempotencyKey

        return .accepted
    }
}
