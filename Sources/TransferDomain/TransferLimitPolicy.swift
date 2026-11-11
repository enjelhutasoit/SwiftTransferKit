//
// Copyright (c) 2026 Enjel Hutasoit
//

/// A cached per-transfer limit used only for local guidance.
///
/// Money guarantees a positive maximum in a supported currency.
/// This value does not establish backend authorization.
public struct TransferLimitPolicy: Equatable, Sendable {
    public let maximumPerTransfer: Money

    public init(maximumPerTransfer: Money) {
        self.maximumPerTransfer = maximumPerTransfer
    }
}

/// Local advice, never an authoritative transfer decision.
public enum TransferPolicyAdvice: Equatable, Sendable {
    case unavailable
    case withinCachedLimit
    case exceedsCachedLimit
}
