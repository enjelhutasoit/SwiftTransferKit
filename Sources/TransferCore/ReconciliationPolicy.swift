//
// Copyright (c) 2026 Enjel Hutasoit
//

public struct ReconciliationPolicy: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidMaximumAttempts
    }

    public let maximumAttempts: Int
    public let retryDelayNanoseconds: UInt64

    public init(
        maximumAttempts: Int = 3,
        retryDelayNanoseconds: UInt64 = 1_000_000_000
    ) throws {
        guard (1...5).contains(maximumAttempts) else {
            throw ValidationError.invalidMaximumAttempts
        }

        self.maximumAttempts = maximumAttempts
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }
}
