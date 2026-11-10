//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum TransferJournalError: Error, Equatable, Sendable {
    case intentConflict
    case idempotencyKeyConflict
    case storageFailure
    case corruptRecord
}
