//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum TransferState: Equatable, Sendable {
    case created
    case submitting

    /// The submission outcome requires authoritative reconciliation.
    case unknown

    /// The server accepted the transfer for processing.
    case accepted

    /// The server confirmed settlement.
    case settled

    /// The server definitively rejected the transfer.
    case rejected
}
