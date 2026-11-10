//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain

/// A gateway bound to a server-authenticated principal in a real adapter.
///
/// Callers do not supply their acting user ID or roles per operation.
public protocol ApprovalGateway: Sendable {
    func createRequest(
        for intent: TransferIntent
    ) async throws -> ApprovalRequest

    func decide(
        approvalID: UUID,
        expectedRevision: UInt64,
        decision: ApprovalDecision
    ) async throws -> ApprovalRequest

    /// Revalidates stored approval before accepting a journaled transfer.
    func submit(
        _ transfer: JournaledTransfer,
        approvalID: UUID,
        expectedRevision: UInt64
    ) async throws -> TransferSubmissionResult
}
