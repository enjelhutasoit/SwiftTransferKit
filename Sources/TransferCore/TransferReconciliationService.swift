//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain

/// Queries status without submitting transfers.
///
/// Retain one instance to preserve ordering knowledge across calls.
/// Snapshots are process-local and do not mutate the durable journal.
public actor TransferReconciliationService {
    public enum Failure: Error, Equatable, Sendable {
        case intentNotFound
        case persistenceFailure
    }

    private struct CachedStatus {
        let idempotencyKey: UUID
        let snapshot: TransferStatusSnapshot
    }

    private let journal: any TransferJournal
    private let gateway: any TransferStatusGateway
    private let policy: ReconciliationPolicy
    private let sleep: @Sendable (UInt64) async throws -> Void

    private var latest: [UUID: CachedStatus] = [:]

    public init(
        journal: any TransferJournal,
        gateway: any TransferStatusGateway,
        policy: ReconciliationPolicy,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        }
    ) {
        self.journal = journal
        self.gateway = gateway
        self.policy = policy
        self.sleep = sleep
    }

    public func latestStatus(
        for intentID: UUID
    ) -> TransferStatusSnapshot? {
        latest[intentID]?.snapshot
    }

    public func reconcile(
        intentID: UUID
    ) async throws -> ReconciliationResult {
        try Task.checkCancellation()

        let storedEntry: JournaledTransfer?

        do {
            storedEntry = try await journal.entry(for: intentID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw Failure.persistenceFailure
        }

        try Task.checkCancellation()

        guard let entry = storedEntry else {
            throw Failure.intentNotFound
        }

        guard entry.intent.id == intentID else {
            throw Failure.persistenceFailure
        }

        for attempt in 1...policy.maximumAttempts {
            try Task.checkCancellation()

            let response: TransferStatusResponse?

            do {
                response = try await gateway.status(
                    for: entry.intent.id,
                    idempotencyKey: entry.idempotencyKey
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                response = nil
            }

            try Task.checkCancellation()

            if let response,
               response.intentID == entry.intent.id,
               response.idempotencyKey == entry.idempotencyKey,
               let state = try confirmedState(for: response.status) {
                let incoming = TransferStatusSnapshot(
                    state: state,
                    version: response.version
                )
                let accepted = try apply(incoming, for: entry)

                return .confirmed(
                    state: accepted.state,
                    attempts: attempt
                )
            }

            guard attempt < policy.maximumAttempts else {
                break
            }

            do {
                try await sleep(policy.retryDelayNanoseconds)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                return .unresolved(attempts: attempt)
            }
        }

        return .unresolved(attempts: policy.maximumAttempts)
    }

    private func apply(
        _ incoming: TransferStatusSnapshot,
        for entry: JournaledTransfer
    ) throws -> TransferStatusSnapshot {
        let current = latest[entry.intent.id]

        if let current,
           current.idempotencyKey != entry.idempotencyKey {
            throw Failure.persistenceFailure
        }

        // Read, validate, and write without a suspension point.
        let merged = try TransferStateMachine.applying(
            incoming,
            to: current?.snapshot
        )

        latest[entry.intent.id] = CachedStatus(
            idempotencyKey: entry.idempotencyKey,
            snapshot: merged
        )

        return merged
    }

    private func confirmedState(
        for status: TransferStatusResponse.Status
    ) throws -> TransferState? {
        let event: TransferEvent

        switch status {
        case .accepted:
            event = .serverAccepted
        case .settled:
            event = .serverSettled
        case .rejected:
            event = .serverRejected
        case .pending, .notFound:
            return nil
        }

        return try TransferStateMachine.transition(
            from: .unknown,
            on: event
        )
    }
}
