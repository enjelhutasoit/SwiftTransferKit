//
// Copyright (c) 2026 Enjel Hutasoit
//

/// A server-issued lifecycle revision scoped to one transfer identity.
///
/// Values are compared numerically, never using client timestamps.
public struct TransferStatusVersion: Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (
        lhs: TransferStatusVersion,
        rhs: TransferStatusVersion
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TransferStatusSnapshot: Equatable, Sendable {
    public let state: TransferState

    /// Nil identifies a legacy observation without ordering metadata.
    public let version: TransferStatusVersion?

    public init(
        state: TransferState,
        version: TransferStatusVersion? = nil
    ) {
        self.state = state
        self.version = version
    }
}
