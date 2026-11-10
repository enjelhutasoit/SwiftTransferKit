//
// Copyright (c) 2026 Enjel Hutasoit
//

/// A positive transfer amount expressed as an exact count of minor units.
public struct Money: Equatable, Sendable {
    public let minorUnits: Int64
    public let currency: Currency

    /// Requires an exact supported currency code and its declared minor-unit scale.
    public init(minorUnits: Int64, currencyCode: String, scale: Int) throws {
        guard let currency = Currency(rawValue: currencyCode) else {
            throw TransferValidationError.unsupportedCurrency
        }
        let expectedScale = currency.minorUnitScale
        guard scale == expectedScale else {
            throw TransferValidationError.invalidScale(expected: expectedScale, actual: scale)
        }

        guard minorUnits > 0 else {
            throw TransferValidationError.nonPositiveAmount
        }
        self.minorUnits = minorUnits
        self.currency = currency
    }
}

