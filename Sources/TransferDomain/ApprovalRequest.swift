//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation

/// An approval snapshot bound to an immutable transfer payload.
///
/// This value is not an authorization token.
public struct ApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let organizationID: UUID
    public let makerID: UUID
    public let intent: TransferIntent
    public let state: ApprovalState
    public let revision: UInt64
    public let decidedBy: UUID?

    public init(
        id: UUID,
        organizationID: UUID,
        makerID: UUID,
        intent: TransferIntent,
        state: ApprovalState,
        revision: UInt64,
        decidedBy: UUID? = nil
    ) {
        self.id = id
        self.organizationID = organizationID
        self.makerID = makerID
        self.intent = intent
        self.state = state
        self.revision = revision
        self.decidedBy = decidedBy
    }
}
