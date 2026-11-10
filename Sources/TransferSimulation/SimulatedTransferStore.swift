//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain

/// In-memory acceptance and lifecycle storage for tests and demos.
public actor SimulatedTransferStore {
    public enum Failure: Error, Equatable, Sendable {
        case transferNotFound
        case versionExhausted
    }

    private struct Record {
        let transfer: JournaledTransfer
        var state: TransferState
        var revision: UInt64

        var snapshot: TransferStatusSnapshot {
            TransferStatusSnapshot(
                state: state,
                version: TransferStatusVersion(rawValue: revision)
            )
        }
    }

    private var acceptedByKey: [UUID: Record] = [:]
    private var keysByIntent: [UUID: UUID] = [:]

    public init() {}

    public var acceptedTransferCount: Int {
        acceptedByKey.count
    }

    public func acceptedTransfer(
        for idempotencyKey: UUID
    ) -> JournaledTransfer? {
        acceptedByKey[idempotencyKey]?.transfer
    }

    /// Returns the original submission acknowledgement on replay.
    func accept(
        _ transfer: JournaledTransfer
    ) throws -> TransferSubmissionResult {
        if let existing = acceptedByKey[transfer.idempotencyKey] {
            guard existing.transfer == transfer else {
                throw SimulatedBankError.idempotencyKeyConflict
            }

            return .accepted
        }

        guard keysByIntent[transfer.intent.id] == nil else {
            throw SimulatedBankError.intentConflict
        }

        acceptedByKey[transfer.idempotencyKey] = Record(
            transfer: transfer,
            state: .accepted,
            revision: 1
        )
        keysByIntent[transfer.intent.id] = transfer.idempotencyKey

        return .accepted
    }

    /// Test/demo control for advancing the simulated server lifecycle.
    ///
    /// Repeating the current state does not create another revision.
    public func advanceStatus(
        for idempotencyKey: UUID,
        to state: TransferState
    ) throws -> TransferStatusSnapshot {
        guard var record = acceptedByKey[idempotencyKey] else {
            throw Failure.transferNotFound
        }

        if state == record.state {
            return record.snapshot
        }

        let next = record.revision.addingReportingOverflow(1)

        guard !next.overflow else {
            throw Failure.versionExhausted
        }

        let incoming = TransferStatusSnapshot(
            state: state,
            version: TransferStatusVersion(rawValue: next.partialValue)
        )
        let merged = try TransferStateMachine.applying(
            incoming,
            to: record.snapshot
        )

        record.state = merged.state
        record.revision = next.partialValue
        acceptedByKey[idempotencyKey] = record

        return record.snapshot
    }

    func status(
        for intentID: UUID,
        idempotencyKey: UUID
    ) throws -> TransferStatusResponse {
        guard let record = acceptedByKey[idempotencyKey] else {
            return TransferStatusResponse(
                intentID: intentID,
                idempotencyKey: idempotencyKey,
                status: .notFound
            )
        }

        guard record.transfer.intent.id == intentID else {
            throw SimulatedBankError.intentConflict
        }

        let status: TransferStatusResponse.Status

        switch record.state {
        case .accepted:
            status = .accepted
        case .settled:
            status = .settled
        case .rejected:
            status = .rejected
        case .created, .submitting, .unknown:
            throw TransferStateMachine.StatusUpdateError.nonAuthoritativeState
        }

        return TransferStatusResponse(
            intentID: record.transfer.intent.id,
            idempotencyKey: record.transfer.idempotencyKey,
            status: status,
            version: TransferStatusVersion(rawValue: record.revision)
        )
    }
}
