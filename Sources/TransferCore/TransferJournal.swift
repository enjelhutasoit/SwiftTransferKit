//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain

public struct JournaledTransfer: Equatable, Sendable {
    public let intent: TransferIntent
    public let idempotencyKey: UUID

    public init(intent: TransferIntent, idempotencyKey: UUID) {
        self.intent = intent
        self.idempotencyKey = idempotencyKey
    }
}

public protocol TransferJournal: Sendable {
    /// Persists a new intent and key before returning.
    ///
    /// Repeating an identical intent returns its original stored key.
    /// A changed payload for an existing identity is rejected.
    /// Callers must use the returned key for subsequent submission.
    func record(
        _ intent: TransferIntent,
        idempotencyKey: UUID
    ) async throws -> JournaledTransfer

    func entry(for intentID: UUID) async throws -> JournaledTransfer?
}
