//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum TransferOperationError: Error, Equatable, Sendable {
    case intentConflict
    case idempotencyKeyConflict
    case persistenceFailure
}
