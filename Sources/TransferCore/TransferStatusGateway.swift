//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation

public struct TransferStatusResponse: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// The server has not yet provided a definitive disposition.
        case pending

        /// Accepted for processing, not necessarily settled.
        case accepted

        case settled
        case rejected

        /// Absence from a lookup does not establish financial rejection.
        case notFound
    }

    public let intentID: UUID
    public let idempotencyKey: UUID
    public let status: Status

    public init(
        intentID: UUID,
        idempotencyKey: UUID,
        status: Status
    ) {
        self.intentID = intentID
        self.idempotencyKey = idempotencyKey
        self.status = status
    }
}

/// Read-only status lookup using previously persisted identity.
///
/// Implementations must bind the response to the requested identity.
/// Each adapter is responsible for its request timeout.
public protocol TransferStatusGateway: Sendable {
    func status(
        for intentID: UUID,
        idempotencyKey: UUID
    ) async throws -> TransferStatusResponse
}
