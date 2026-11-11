//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain

/// Coordinates submissions within one process and one coordinator instance.
///
/// Callers must reuse the same intent identity for the same business action.
/// Backend idempotency remains required across instances and devices.
public actor TransferCoordinator {
    private struct TrackedTransfer {
        let intent: TransferIntent
        let correlationID: UUID
        var state: TransferState
        var failure: TransferFailure? = nil
    }

    private let journal: any TransferJournal
    private let gateway: any TransferGateway
    private let diagnostics: any TransferDiagnostics
    private let makeCorrelationID: @Sendable () -> UUID
    private let makeIdempotencyKey: @Sendable () -> UUID

    private var tracked: [UUID: TrackedTransfer] = [:]

    public init(
        journal: any TransferJournal,
        gateway: any TransferGateway,
        diagnostics: any TransferDiagnostics = NoOpTransferDiagnostics(),
        makeCorrelationID: @escaping @Sendable () -> UUID = { UUID() },
        makeIdempotencyKey: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.journal = journal
        self.gateway = gateway
        self.diagnostics = diagnostics
        self.makeCorrelationID = makeCorrelationID
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    /// Submits a new intent after persistence succeeds.
    ///
    /// An identical concurrent call returns `.submitting` immediately.
    /// Repeated calls return the current local state without resubmitting.
    /// Gateway errors preserve `.unknown`; they do not establish rejection.
    /// Operational causes can be read using `failure(for:)`.
    public func submit(
        _ intent: TransferIntent
    ) async throws -> TransferState {
        if let existing = tracked[intent.id] {
            guard existing.intent == intent else {
                emit(
                    .intentConflict,
                    correlationID: existing.correlationID
                )
                throw TransferOperationError.intentConflict
            }

            emit(
                .submissionReused,
                correlationID: existing.correlationID
            )
            return existing.state
        }

        let submittingState = try TransferStateMachine.transition(
            from: .created,
            on: .submissionStarted
        )
        let correlationID = makeCorrelationID()

        // Reserve before the first suspension point.
        tracked[intent.id] = TrackedTransfer(
            intent: intent,
            correlationID: correlationID,
            state: submittingState
        )
        emit(.submissionStarted, correlationID: correlationID)

        let prepared: JournaledTransfer?

        do {
            prepared = try await prepareSubmission(for: intent)
        } catch {
            // The gateway has not been called by this attempt.
            // A later attempt must check the journal again.
            tracked.removeValue(forKey: intent.id)
            emit(.preparationFailed, correlationID: correlationID)
            throw error
        }

        guard let prepared else {
            tracked[intent.id]?.state = .unknown
            tracked[intent.id]?.failure = .unknownOutcome
            emit(.reconciliationRequired, correlationID: correlationID)
            return .unknown
        }

        emit(.intentJournaled, correlationID: correlationID)

        let result: TransferSubmissionResult

        do {
            result = try await gateway.submit(prepared)
        } catch {
            // Operational failure does not establish financial rejection.
            tracked[intent.id]?.state = .unknown
            tracked[intent.id]?.failure = classifySubmissionFailure(error)
            emit(.submissionUnresolved, correlationID: correlationID)
            return .unknown
        }

        let event: TransferEvent
        let diagnosticName: TransferDiagnosticEvent.Name

        switch result {
        case .accepted:
            event = .serverAccepted
            diagnosticName = .submissionAccepted

        case .rejected:
            event = .serverRejected
            diagnosticName = .submissionRejected
        }

        let finalState = try TransferStateMachine.transition(
            from: submittingState,
            on: event
        )
        tracked[intent.id]?.state = finalState
        tracked[intent.id]?.failure = nil
        emit(diagnosticName, correlationID: correlationID)
        return finalState
    }

    /// Returns only the state observed by this coordinator.
    ///
    /// A nil result does not prove the intent is absent from durable storage.
    public func state(for intentID: UUID) -> TransferState? {
        tracked[intentID]?.state
    }

    /// Returns the operational cause observed during submission.
    ///
    /// This value is local to this coordinator and is not persisted.
    /// Nil does not imply acceptance, settlement, or absence of other errors.
    /// Preparation errors continue to be thrown by submit(_:).
    public func failure(for intentID: UUID) -> TransferFailure? {
        tracked[intentID]?.failure
    }

    private func prepareSubmission(
        for intent: TransferIntent
    ) async throws -> JournaledTransfer? {
        let existingEntry: JournaledTransfer?

        do {
            existingEntry = try await journal.entry(for: intent.id)
        } catch {
            throw mapJournalError(error)
        }

        guard try TransferSubmissionPolicy.shouldSubmit(
            intent,
            existingEntry: existingEntry
        ) else {
            return nil
        }

        do {
            let entry = try await journal.record(
                intent,
                idempotencyKey: makeIdempotencyKey()
            )

            guard entry.intent == intent else {
                throw TransferJournalError.corruptRecord
            }

            // The journal may return an already stored key.
            // Its returned entry is the submission source of truth.
            return entry
        } catch {
            throw mapJournalError(error)
        }
    }

    private func classifySubmissionFailure(
        _ error: any Error
    ) -> TransferFailure {
        if let classified = error as? any TransferFailureProviding {
            return classified.transferFailure
        }

        if error is CancellationError {
            return .cancelled
        }

        return .unknownOutcome
    }

    private func mapJournalError(
        _ error: any Error
    ) -> TransferOperationError {
        guard let journalError = error as? TransferJournalError else {
            return .persistenceFailure
        }

        switch journalError {
        case .intentConflict:
            return .intentConflict

        case .idempotencyKeyConflict:
            return .idempotencyKeyConflict

        case .storageFailure, .corruptRecord:
            return .persistenceFailure
        }
    }

    private func emit(
        _ name: TransferDiagnosticEvent.Name,
        correlationID: UUID
    ) {
        let event = TransferDiagnosticEvent(
            name: name,
            correlationID: correlationID
        )

        // Diagnostics must not replace a business result or error.
        // Do not recursively log sink failures.
        try? diagnostics.record(event)
    }
}
