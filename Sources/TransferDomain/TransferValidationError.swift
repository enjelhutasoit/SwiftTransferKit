//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum TransferValidationError: Error, Equatable, Sendable {
    case unsupportedCurrency
    case invalidScale(expected: Int, actual: Int)
    case nonPositiveAmount
}
