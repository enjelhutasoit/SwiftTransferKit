//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain

public enum ReconciliationResult: Equatable, Sendable {
    /// A matching response established an authoritative observed state.
    /// Acceptance still does not mean settlement.
    case confirmed(state: TransferState, attempts: Int)

    /// No trustworthy disposition was obtained.
    /// Preserve the caller's previously known financial state.
    case unresolved(attempts: Int)
}
