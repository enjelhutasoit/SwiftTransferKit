//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation

/// An allowlisted diagnostic payload without transfer or credential data.
public struct TransferDiagnosticEvent: Equatable, Encodable, Sendable {
    public enum Name: String, Encodable, Sendable {
        case submissionStarted = "submission_started"
        case intentJournaled = "intent_journaled"
        case submissionAccepted = "submission_accepted"
        case submissionRejected = "submission_rejected"
        case submissionUnresolved = "submission_unresolved"
        case submissionReused = "submission_reused"
        case reconciliationRequired = "reconciliation_required"
        case preparationFailed = "preparation_failed"
        case intentConflict = "intent_conflict"
    }

    public let name: Name
    public let correlationID: UUID

    /// Use a fresh opaque correlation ID, not a business or credential ID.
    public init(name: Name, correlationID: UUID) {
        self.name = name
        self.correlationID = correlationID
    }
}
