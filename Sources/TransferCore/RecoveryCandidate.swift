//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain

/// A journaled intent and the observation obtained during recovery.
public struct RecoveryCandidate: Identifiable, Equatable, Sendable {
    public enum Classification: Equatable, Sendable {
        case unresolved
        case processing
        case completed
    }

    public let entry: JournaledTransfer
    public let reconciliation: ReconciliationResult

    public var id: UUID {
        entry.intent.id
    }

    public var classification: Classification {
        switch reconciliation {
        case .confirmed(state: .accepted, attempts: _):
            return .processing

        case .confirmed(state: .settled, attempts: _),
             .confirmed(state: .rejected, attempts: _):
            return .completed

        default:
            return .unresolved
        }
    }

    init(
        entry: JournaledTransfer,
        reconciliation: ReconciliationResult
    ) {
        self.entry = entry
        self.reconciliation = reconciliation
    }
}
