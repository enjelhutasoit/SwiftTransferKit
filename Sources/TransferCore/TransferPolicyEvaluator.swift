//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain

public enum TransferPolicyEvaluator {
    /// Returns local guidance without blocking submission.
    ///
    /// The backend remains authoritative even when cached advice differs
    /// from the eventual submission result.
    public static func evaluate(
        _ amount: Money,
        cachedPolicy: TransferLimitPolicy?
    ) -> TransferPolicyAdvice {
        guard let cachedPolicy else {
            return .unavailable
        }

        let maximum = cachedPolicy.maximumPerTransfer

        guard amount.currency == maximum.currency else {
            return .unavailable
        }

        return amount.minorUnits <= maximum.minorUnits
            ? .withinCachedLimit
            : .exceedsCachedLimit
    }
}
