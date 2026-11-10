//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain

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

    /// Server-issued revision for an authoritative financial status.
    ///
    /// Nil supports legacy adapters. The client must not fabricate a value.
    /// Pending/not-found observations do not advance the financial revision.
    public let version: TransferStatusVersion?

    public init(
        intentID: UUID,
        idempotencyKey: UUID,
        status: Status,
        version: TransferStatusVersion? = nil
    ) {
        self.intentID = intentID
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.version = version
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
