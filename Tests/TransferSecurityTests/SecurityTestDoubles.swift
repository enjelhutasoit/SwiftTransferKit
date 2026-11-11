//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferSecurity

enum SecurityFixtures {
    static let now = Date(timeIntervalSince1970: 100)
    static let secret = "sensitive-test-token"

    static let identity = SessionIdentity(
        organizationID: UUID(),
        userID: UUID()
    )

    static func credential(
        identity: SessionIdentity = SecurityFixtures.identity,
        expiresAt: Date = Date(timeIntervalSince1970: 200)
    ) throws -> SessionCredential {
        try SessionCredential(
            id: UUID(),
            identity: identity,
            accessToken: secret,
            expiresAt: expiresAt
        )
    }

    static func transfer() throws -> JournaledTransfer {
        JournaledTransfer(
            intent: TransferIntent(
                id: UUID(),
                amount: try Money(
                    minorUnits: 10_000,
                    currencyCode: "IDR",
                    scale: 2
                )
            ),
            idempotencyKey: UUID()
        )
    }
}

struct SensitiveFailure: Error, CustomStringConvertible {
    var description: String {
        SecurityFixtures.secret
    }
}

actor CredentialStoreStub: CredentialStore {
    private var credential: SessionCredential?
    private let failsToLoad: Bool

    init(
        credential: SessionCredential?,
        failsToLoad: Bool = false
    ) {
        self.credential = credential
        self.failsToLoad = failsToLoad
    }

    func load() async throws -> SessionCredential? {
        if failsToLoad {
            throw SensitiveFailure()
        }

        return credential
    }

    func save(_ credential: SessionCredential) async throws {
        self.credential = credential
    }

    func delete() async throws {
        credential = nil
    }
}

actor SecurityClock {
    private var value: Date

    init(_ value: Date = SecurityFixtures.now) {
        self.value = value
    }

    func now() -> Date {
        value
    }

    func set(_ value: Date) {
        self.value = value
    }
}

@MainActor
final class StepUpAuthenticatorStub: StepUpAuthenticator {
    private(set) var callCount = 0

    private let action: @MainActor @Sendable () async throws -> Void

    init(
        action: @escaping @MainActor @Sendable () async throws -> Void = {}
    ) {
        self.action = action
    }

    func authenticate(reason: String) async throws {
        callCount += 1
        try await action()
    }
}

actor SubmissionGatewaySpy: TransferGateway {
    private(set) var submissions: [JournaledTransfer] = []

    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        submissions.append(transfer)
        return .accepted
    }
}
