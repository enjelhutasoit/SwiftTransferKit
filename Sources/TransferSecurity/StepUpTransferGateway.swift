//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferCore

/// Applies local session and user-presence checks before submission.
///
/// The underlying gateway remains responsible for authenticated transport.
/// The backend remains authoritative for authorization and financial state.
public struct StepUpTransferGateway: TransferGateway {
    private let sessions: SessionProvider
    private let expectedIdentity: SessionIdentity
    private let authenticator: any StepUpAuthenticator
    private let underlying: any TransferGateway
    private let reason: String

    public init(
        sessions: SessionProvider,
        expectedIdentity: SessionIdentity,
        authenticator: any StepUpAuthenticator,
        underlying: any TransferGateway,
        reason: String = "Confirm this transfer."
    ) {
        self.sessions = sessions
        self.expectedIdentity = expectedIdentity
        self.authenticator = authenticator
        self.underlying = underlying
        self.reason = reason
    }

    public func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        let initialSession = try await sessions.validSession(
            for: expectedIdentity
        )

        do {
            try await authenticator.authenticate(reason: reason)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as StepUpError {
            try Task.checkCancellation()
            throw error
        } catch {
            try Task.checkCancellation()
            throw StepUpError.failed
        }

        let currentSession = try await sessions.validSession(
            for: expectedIdentity
        )

        guard currentSession == initialSession else {
            throw SessionError.sessionChanged
        }

        try Task.checkCancellation()

        return try await underlying.submit(transfer)
    }
}
