//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation

public struct SessionIdentity: Codable, Equatable, Sendable {
    public let organizationID: UUID
    public let userID: UUID

    public init(organizationID: UUID, userID: UUID) {
        self.organizationID = organizationID
        self.userID = userID
    }
}

public enum SessionError: Error, Equatable, Sendable {
    case invalidCredential
    case missingSession
    case expiredSession
    case identityMismatch
    case sessionChanged
    case credentialUnavailable
}

/// A locally stored credential, not proof of backend authorization.
///
/// Encoded data and explicit transport access contain the token.
/// String descriptions and reflection intentionally redact it.
public struct SessionCredential:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public let id: UUID
    public let identity: SessionIdentity
    public let expiresAt: Date

    private let accessToken: String

    public init(
        id: UUID = UUID(),
        identity: SessionIdentity,
        accessToken: String,
        expiresAt: Date
    ) throws {
        guard !accessToken.isEmpty,
              !accessToken.unicodeScalars.contains(
                  where: { CharacterSet.whitespacesAndNewlines.contains($0) }
              ),
              !accessToken.unicodeScalars.contains(
                  where: { CharacterSet.controlCharacters.contains($0) }
              ),
              expiresAt.timeIntervalSince1970.isFinite else {
            throw SessionError.invalidCredential
        }

        self.id = id
        self.identity = identity
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// Returns sensitive data for an authenticated transport adapter.
    /// Never include this value in logs or diagnostics.
    public func accessTokenForTransport() -> String {
        accessToken
    }

    public var description: String {
        "SessionCredential(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["credential": "<redacted>"])
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case identity
        case expiresAt
        case accessToken
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            identity: container.decode(
                SessionIdentity.self,
                forKey: .identity
            ),
            accessToken: container.decode(
                String.self,
                forKey: .accessToken
            ),
            expiresAt: container.decode(Date.self, forKey: .expiresAt)
        )
    }
}

public protocol CredentialStore: Sendable {
    func load() async throws -> SessionCredential?
    func save(_ credential: SessionCredential) async throws
    func delete() async throws
}

/// Validates local session metadata without asserting server validity.
public struct SessionProvider: Sendable {
    private let store: any CredentialStore
    private let now: @Sendable () async -> Date

    public init(
        store: any CredentialStore,
        now: @escaping @Sendable () async -> Date = { Date() }
    ) {
        self.store = store
        self.now = now
    }

    public func validSession(
        for expectedIdentity: SessionIdentity
    ) async throws -> SessionCredential {
        try Task.checkCancellation()

        let stored: SessionCredential?

        do {
            stored = try await store.load()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw SessionError.credentialUnavailable
        }

        try Task.checkCancellation()

        guard let credential = stored else {
            throw SessionError.missingSession
        }

        guard credential.identity == expectedIdentity else {
            throw SessionError.identityMismatch
        }

        let currentTime = await now()
        try Task.checkCancellation()

        guard currentTime < credential.expiresAt else {
            throw SessionError.expiredSession
        }

        return credential
    }
}
