//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation

struct TransferResponseDTO: Decodable {
    enum Status: String, Decodable {
        case accepted
        case rejected
    }

    let intentID: UUID
    let status: Status
}
