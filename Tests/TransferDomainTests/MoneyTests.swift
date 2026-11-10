//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain
import XCTest

final class MoneyTests: XCTestCase {
    func testPreservesExactIDRMinorUnitsBeyondBinaryFloatingPointPrecision() throws {
        let minorUnits: Int64 = 9_007_199_254_740_993
        let money = try Money(minorUnits: minorUnits, currencyCode: "IDR", scale: 2)
        
        XCTAssertEqual(money.minorUnits, minorUnits)
        XCTAssertEqual(money.currency, .idr)
        XCTAssertEqual(money.currency.rawValue, "IDR")
        XCTAssertEqual(money.currency.minorUnitScale, 2)
    }
    
    func testRejectsUnsupportedCurrency() {
        XCTAssertThrowsError(try Money(minorUnits: 100, currencyCode: "USD", scale: 2)) { error in
            XCTAssertEqual(error as? TransferValidationError, .unsupportedCurrency)
        }
    }

    func testRejectsScalesThatDoNotMatchIDR() {
        for scale in [0, 3] {
            XCTAssertThrowsError(try Money(minorUnits: 100, currencyCode: "IDR", scale: scale)) { error in
                XCTAssertEqual(error as? TransferValidationError, .invalidScale(expected: 2, actual: scale))
            }
        }
    }

    func testRejectsZeroAndNegativeAmounts() {
        let invalidAmounts: [Int64] = [0, -1]

        for minorUnits in invalidAmounts {
            XCTAssertThrowsError(try Money(minorUnits: minorUnits, currencyCode: "IDR", scale: 2)) { error in
                XCTAssertEqual(error as? TransferValidationError, .nonPositiveAmount)
            }
        }
    }

}
