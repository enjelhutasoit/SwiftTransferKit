//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum ApprovalState: Equatable, Sendable {
    case pending
    case approved
    case rejected
}

public enum ApprovalDecision: Equatable, Sendable {
    case approve
    case reject
}

public enum ApprovalError: Error, Equatable, Sendable {
    case unauthorized
    case selfApproval
    case requestNotFound
    case staleRevision
    case alreadyDecided
    case intentConflict
    case approvalRequired
    case approvalRejected
    case invalidConfiguration
}
