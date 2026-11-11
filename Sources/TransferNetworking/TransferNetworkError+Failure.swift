//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain

extension TransferNetworkError: TransferFailureProviding {
    public var transferFailure: TransferFailure {
        switch self {
        case .invalidEndpoint, .requestEncodingFailed:
            return .configurationFailure

        case .timedOut, .transportFailure:
            return .transportFailure

        case .invalidResponse:
            return .invalidResponse

        case .unexpectedHTTPStatus(let statusCode):
            switch statusCode {
            case 401:
                return .authenticationRequired

            case 403:
                return .authorizationDenied

            default:
                return .invalidResponse
            }
        }
    }
}
