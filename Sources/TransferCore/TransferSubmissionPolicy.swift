//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain

enum TransferSubmissionPolicy {
    /// Existing journal entries require reconciliation when their outcome
    /// is not already known by the current coordinator.
    static func shouldSubmit(
        _ intent: TransferIntent,
        existingEntry: JournaledTransfer?
    ) throws -> Bool {
        guard let existingEntry else {
            return true
        }

        guard existingEntry.intent == intent else {
            throw TransferOperationError.intentConflict
        }

        return false
    }
}
