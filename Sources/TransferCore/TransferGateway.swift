//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum TransferSubmissionResult: Equatable, Sendable {
    case accepted
    case rejected
}

/// Submits a transfer using its previously persisted identity and key.
///
/// Acceptance does not mean settlement.
/// A thrown error does not establish financial rejection.
public protocol TransferGateway: Sendable {
    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult
}
