//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain

struct TransferRequestDTO: Encodable {
    let intentID: UUID
    let minorUnits: Int64
    let currency: String
    let scale: Int

    init(transfer: JournaledTransfer) {
        intentID = transfer.intent.id
        minorUnits = transfer.intent.amount.minorUnits
        currency = transfer.intent.amount.currency.rawValue
        scale = transfer.intent.amount.currency.minorUnitScale
    }
}
