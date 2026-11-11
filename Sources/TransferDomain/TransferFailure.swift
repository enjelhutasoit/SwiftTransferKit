//
// Copyright (c) 2026 Enjel Hutasoit
//

/// A suggested user or host-app action, not an automatic retry instruction.
///
/// Authentication does not authorize resubmission.
/// Journaled intents must retain their identity and follow reconciliation.
public enum TransferFailureAction: Equatable, Sendable {
    case correctInput
    case signIn
    case authenticate
    case checkAuthenticationAvailability
    case reviewAccess
    case reviewConfiguration
    case reconcile
}

/// Allows adapters to expose a safe, module-independent failure category.
public protocol TransferFailureProviding: Error {
    var transferFailure: TransferFailure { get }
}

/// An operational failure category, separate from financial transfer state.
///
/// No case in this type proves that a transfer was rejected or settled.
public enum TransferFailure:
    Error,
    Equatable,
    Sendable,
    TransferFailureProviding
{
    case invalidInput
    case authenticationRequired
    case stepUpRequired
    case authenticationUnavailable
    case authorizationDenied
    case cancelled
    case transportFailure
    case invalidResponse
    case configurationFailure
    case unknownOutcome

    public var transferFailure: TransferFailure {
        self
    }

    public var suggestedAction: TransferFailureAction {
        switch self {
        case .invalidInput:
            return .correctInput

        case .authenticationRequired:
            return .signIn

        case .stepUpRequired:
            return .authenticate

        case .authenticationUnavailable:
            return .checkAuthenticationAvailability

        case .authorizationDenied:
            return .reviewAccess

        case .configurationFailure:
            return .reviewConfiguration

        case .cancelled, .transportFailure, .invalidResponse, .unknownOutcome:
            return .reconcile
        }
    }
}

extension TransferValidationError: TransferFailureProviding {
    public var transferFailure: TransferFailure {
        .invalidInput
    }
}
