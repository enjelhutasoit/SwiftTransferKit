//
// Copyright (c) 2026 Enjel Hutasoit
//

/// Scans durable identities and reconciles them without resubmission.
///
/// Keep one instance in the host composition root.
/// The host invokes recovery on launch or activation.
public actor TransferRecoveryService {
    public enum Failure: Error, Equatable, Sendable {
        case recoveryInProgress
        case journalUnavailable
        case reconciliationFailed
    }

    private let journal: any TransferRecoveryJournal
    private let reconciliation: TransferReconciliationService
    private var isRecovering = false

    public init(
        journal: any TransferRecoveryJournal,
        gateway: any TransferStatusGateway,
        policy: ReconciliationPolicy,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        }
    ) {
        self.journal = journal
        reconciliation = TransferReconciliationService(
            journal: journal,
            gateway: gateway,
            policy: policy,
            sleep: sleep
        )
    }

    /// Returns a complete report for the scanned entries.
    ///
    /// Cancellation or a local storage failure aborts the report.
    /// No journal entry is changed or removed by recovery.
    public func recover() async throws -> [RecoveryCandidate] {
        try Task.checkCancellation()

        guard !isRecovering else {
            throw Failure.recoveryInProgress
        }

        isRecovering = true
        defer { isRecovering = false }

        let entries: [JournaledTransfer]

        do {
            entries = try await journal.allEntries()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw Failure.journalUnavailable
        }

        try Task.checkCancellation()

        var candidates: [RecoveryCandidate] = []
        candidates.reserveCapacity(entries.count)

        for entry in entries {
            try Task.checkCancellation()

            let result: ReconciliationResult

            do {
                result = try await reconciliation.reconcile(
                    intentID: entry.intent.id
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch is TransferReconciliationService.Failure {
                try Task.checkCancellation()
                throw Failure.journalUnavailable
            } catch {
                try Task.checkCancellation()
                throw Failure.reconciliationFailed
            }

            try Task.checkCancellation()

            candidates.append(
                RecoveryCandidate(
                    entry: entry,
                    reconciliation: result
                )
            )
        }

        return candidates
    }
}
