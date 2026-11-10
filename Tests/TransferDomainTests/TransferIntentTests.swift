//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferDomain
import XCTest

final class TransferIntentTests: XCTestCase {
    func testReconstructingIntentPreservesIdentityAndAmount() throws {
        let id = try XCTUnwrap(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        let amount = try Money(minorUnits: 125_050, currencyCode: "IDR", scale: 2)
        let original = TransferIntent(id: id, amount: amount)
        let reconstructed = TransferIntent(id: id, amount: amount)

        XCTAssertEqual(original.id, id)
        XCTAssertEqual(original.amount, amount)
        XCTAssertEqual(reconstructed, original)
    }

    func testDifferentIDsDistinguishIntentsWithTheSameAmount() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        let secondID = try XCTUnwrap(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let amount = try Money(minorUnits: 125_050, currencyCode: "IDR", scale: 2)

        XCTAssertNotEqual(
            TransferIntent(id: firstID, amount: amount),
            TransferIntent(id: secondID, amount: amount)
        )
    }
}
