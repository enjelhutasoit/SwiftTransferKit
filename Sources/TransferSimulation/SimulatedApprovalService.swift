//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain

/// In-memory approval authority for one simulated organization.
///
/// Membership and session creation are trusted test/demo configuration.
/// Use a dedicated transfer store for each simulated organization.
public actor SimulatedApprovalService {
    private let organizationID: UUID
    private let members: [UUID: BusinessContext]
    private let store: SimulatedTransferStore
    private let makeApprovalID: @Sendable () -> UUID

    private var requests: [UUID: ApprovalRequest] = [:]
    private var approvalIDsByIntent: [UUID: UUID] = [:]

    public init(
        organizationID: UUID,
        members: [BusinessContext],
        store: SimulatedTransferStore = SimulatedTransferStore(),
        makeApprovalID: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        var directory: [UUID: BusinessContext] = [:]

        for member in members {
            guard member.organizationID == organizationID,
                  directory[member.userID] == nil else {
                throw ApprovalError.invalidConfiguration
            }

            directory[member.userID] = member
        }

        self.organizationID = organizationID
        self.members = directory
        self.store = store
        self.makeApprovalID = makeApprovalID
    }

    /// Creates a simulated principal-bound session.
    ///
    /// This fixture factory is not real authentication.
    public func gateway(
        for userID: UUID
    ) throws -> any ApprovalGateway {
        guard members[userID] != nil else {
            throw ApprovalError.unauthorized
        }

        return Session(server: self, userID: userID)
    }

    private func createRequest(
        for intent: TransferIntent,
        userID: UUID
    ) throws -> ApprovalRequest {
        let member = try context(for: userID, requiring: .maker)

        if let existingID = approvalIDsByIntent[intent.id],
           let existing = requests[existingID] {
            guard existing.intent == intent,
                  existing.makerID == member.userID else {
                throw ApprovalError.intentConflict
            }

            return existing
        }

        let approvalID = makeApprovalID()

        guard requests[approvalID] == nil else {
            throw ApprovalError.invalidConfiguration
        }

        let request = ApprovalRequest(
            id: approvalID,
            organizationID: organizationID,
            makerID: member.userID,
            intent: intent,
            state: .pending,
            revision: 1
        )

        requests[approvalID] = request
        approvalIDsByIntent[intent.id] = approvalID

        return request
    }

    private func decide(
        approvalID: UUID,
        expectedRevision: UInt64,
        decision: ApprovalDecision,
        userID: UUID
    ) throws -> ApprovalRequest {
        let member = try context(for: userID, requiring: .checker)
        let current = try request(for: approvalID)

        guard current.makerID != member.userID else {
            throw ApprovalError.selfApproval
        }

        guard current.revision == expectedRevision else {
            throw ApprovalError.staleRevision
        }

        guard current.state == .pending else {
            throw ApprovalError.alreadyDecided
        }

        let state: ApprovalState

        switch decision {
        case .approve:
            state = .approved
        case .reject:
            state = .rejected
        }

        // A pending request is server-created at revision 1.
        // Decisions are final, so the only next revision is 2.
        let updated = ApprovalRequest(
            id: current.id,
            organizationID: current.organizationID,
            makerID: current.makerID,
            intent: current.intent,
            state: state,
            revision: current.revision + 1,
            decidedBy: member.userID
        )

        // Revision validation and mutation have no suspension point.
        requests[approvalID] = updated
        return updated
    }

    private func submit(
        _ transfer: JournaledTransfer,
        approvalID: UUID,
        expectedRevision: UInt64,
        userID: UUID
    ) async throws -> TransferSubmissionResult {
        let member = try context(for: userID, requiring: .maker)
        let approval = try request(for: approvalID)

        guard approval.makerID == member.userID else {
            throw ApprovalError.unauthorized
        }

        guard approval.revision == expectedRevision else {
            throw ApprovalError.staleRevision
        }

        guard approval.intent == transfer.intent else {
            throw ApprovalError.intentConflict
        }

        switch approval.state {
        case .pending:
            throw ApprovalError.approvalRequired
        case .rejected:
            throw ApprovalError.approvalRejected
        case .approved:
            break
        }

        // Membership is fixed and decided approvals cannot be changed
        // by this simulator while the store operation is suspended.
        return try await store.accept(transfer)
    }

    private func context(
        for userID: UUID,
        requiring role: BusinessRole
    ) throws -> BusinessContext {
        guard let member = members[userID],
              member.roles.contains(role) else {
            throw ApprovalError.unauthorized
        }

        return member
    }

    private func request(
        for approvalID: UUID
    ) throws -> ApprovalRequest {
        guard let request = requests[approvalID],
              request.organizationID == organizationID else {
            throw ApprovalError.requestNotFound
        }

        return request
    }

    private struct Session: ApprovalGateway {
        let server: SimulatedApprovalService
        let userID: UUID

        func createRequest(
            for intent: TransferIntent
        ) async throws -> ApprovalRequest {
            try await server.createRequest(
                for: intent,
                userID: userID
            )
        }

        func decide(
            approvalID: UUID,
            expectedRevision: UInt64,
            decision: ApprovalDecision
        ) async throws -> ApprovalRequest {
            try await server.decide(
                approvalID: approvalID,
                expectedRevision: expectedRevision,
                decision: decision,
                userID: userID
            )
        }

        func submit(
            _ transfer: JournaledTransfer,
            approvalID: UUID,
            expectedRevision: UInt64
        ) async throws -> TransferSubmissionResult {
            try await server.submit(
                transfer,
                approvalID: approvalID,
                expectedRevision: expectedRevision,
                userID: userID
            )
        }
    }
}
