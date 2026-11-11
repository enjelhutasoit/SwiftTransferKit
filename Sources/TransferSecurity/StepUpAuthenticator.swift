//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum StepUpError: Error, Equatable, Sendable {
    case invalidReason
    case unavailable
    case alreadyInProgress
    case cancelled
    case failed
}

/// Establishes local user presence, not backend transfer authorization.
@MainActor
public protocol StepUpAuthenticator: Sendable {
    func authenticate(reason: String) async throws
}
