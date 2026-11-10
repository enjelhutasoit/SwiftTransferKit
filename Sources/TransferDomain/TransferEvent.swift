//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum TransferEvent: Equatable, Sendable {
    case submissionStarted
    case submissionTimedOut

    /// Emitted from an authoritative response for this intent.
    case serverAccepted

    /// Emitted from an authoritative response for this intent.
    case serverSettled

    /// Emitted from an authoritative response for this intent.
    case serverRejected
}
