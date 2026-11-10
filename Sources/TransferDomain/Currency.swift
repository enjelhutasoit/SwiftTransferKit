//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum Currency: String, Equatable, Sendable {
    case idr = "IDR"

    /// The number of decimal places represented by minor units.
    public var minorUnitScale: Int {
        switch self {
        case .idr:
            return 2
        }
    }
}
