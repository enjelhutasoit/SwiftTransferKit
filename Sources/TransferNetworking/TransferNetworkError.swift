//
// Copyright (c) 2026 Enjel Hutasoit
//

/// Safe public diagnostics without raw transport errors or response bodies.
public enum TransferNetworkError: Error, Equatable, Sendable {
    case invalidEndpoint
    case requestEncodingFailed
    case timedOut
    case transportFailure
    case invalidResponse
    case unexpectedHTTPStatus(Int)
}
