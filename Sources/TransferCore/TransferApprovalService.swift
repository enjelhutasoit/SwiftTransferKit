//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain

public struct TransferApprovalService: Sendable {
    private let gateway: any ApprovalGateway

    public init(gateway: any ApprovalGateway) {
        self.gateway = gateway
    }

    public func requestApproval(
        for intent: TransferIntent
    ) async throws -> ApprovalRequest {
        try await gateway.createRequest(for: intent)
    }

    public func decide(
        _ request: ApprovalRequest,
        decision: ApprovalDecision
    ) async throws -> ApprovalRequest {
        try await gateway.decide(
            approvalID: request.id,
            expectedRevision: request.revision,
            decision: decision
        )
    }

    /// Performs an advisory local check and returns a coordinator adapter.
    ///
    /// The backend must still validate its own stored approval at submission.
    public func submissionGateway(
        for request: ApprovalRequest
    ) throws -> any TransferGateway {
        switch request.state {
        case .pending:
            throw ApprovalError.approvalRequired

        case .rejected:
            throw ApprovalError.approvalRejected

        case .approved:
            return ApprovalSubmissionGateway(
                gateway: gateway,
                approvalID: request.id,
                expectedRevision: request.revision
            )
        }
    }
}

private struct ApprovalSubmissionGateway: TransferGateway {
    let gateway: any ApprovalGateway
    let approvalID: UUID
    let expectedRevision: UInt64

    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        try await gateway.submit(
            transfer,
            approvalID: approvalID,
            expectedRevision: expectedRevision
        )
    }
}
