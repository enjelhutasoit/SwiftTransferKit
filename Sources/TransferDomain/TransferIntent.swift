//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation

public struct TransferIntent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let amount: Money

    /// Pass the original ID when reconstructing the same intent.
    public init(id: UUID, amount: Money) {
        self.id = id
        self.amount = amount
    }
}
