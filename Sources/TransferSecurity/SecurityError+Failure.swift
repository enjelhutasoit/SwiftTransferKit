//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain

extension SessionError: TransferFailureProviding {
    public var transferFailure: TransferFailure {
        switch self {
        case .invalidCredential,
             .missingSession,
             .expiredSession,
             .identityMismatch,
             .sessionChanged:
            return .authenticationRequired

        case .credentialUnavailable:
            return .authenticationUnavailable
        }
    }
}

extension StepUpError: TransferFailureProviding {
    public var transferFailure: TransferFailure {
        switch self {
        case .invalidReason:
            return .configurationFailure

        case .unavailable:
            return .authenticationUnavailable

        case .alreadyInProgress, .failed:
            return .stepUpRequired

        case .cancelled:
            return .cancelled
        }
    }
}
