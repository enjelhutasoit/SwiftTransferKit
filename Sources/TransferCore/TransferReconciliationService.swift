//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain

/// Queries status for an existing journaled intent without submitting it.
///
/// Returns an observation; it does not mutate the journal or coordinator.
/// Status ordering across separate calls is handled by a later layer.
public struct TransferReconciliationService: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case intentNotFound
        case persistenceFailure
    }

    private let journal: any TransferJournal
    private let gateway: any TransferStatusGateway
    private let policy: ReconciliationPolicy
    private let sleep: @Sendable (UInt64) async throws -> Void

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
                return .confirmed(state: state, attempts: attempt)
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
