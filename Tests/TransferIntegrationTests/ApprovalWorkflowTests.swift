//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferPersistence
import TransferSecurity
import TransferSimulation
import XCTest

@MainActor
final class ApprovalWorkflowTests: XCTestCase {
    func test_unauthorizedDecision_cannotAuthorizeJournaledSubmission() async throws {
        let fixture = try await makeFixture()

        try await IntegrationFixtures.withJournal { _, journal in
            let pending = try await fixture.maker.requestApproval(
                for: fixture.transfer.intent
            )

            do {
                _ = try await fixture.viewer.decide(
                    approvalID: pending.id,
                    expectedRevision: pending.revision,
                    decision: .approve
                )
                XCTFail("Expected unauthorized checker rejection.")
            } catch {
                XCTAssertEqual(error as? ApprovalError, .unauthorized)
            }

            // A client-side approved snapshot must not authorize the transfer.
            let forged = ApprovalRequest(
                id: pending.id,
                organizationID: pending.organizationID,
                makerID: pending.makerID,
                intent: pending.intent,
                state: .approved,
                revision: pending.revision
            )
            let gateway = try fixture.maker.submissionGateway(
                for: forged
            )
            let coordinator = TransferCoordinator(
                journal: journal,
                gateway: gateway,
                makeIdempotencyKey: {
                    fixture.transfer.idempotencyKey
                }
            )

            let state = try await coordinator.submit(
                fixture.transfer.intent
            )
            let persisted = try await journal.entry(
                for: fixture.transfer.intent.id
            )
            let acceptedCount = await fixture.store.acceptedTransferCount

            XCTAssertEqual(state, .unknown)
            XCTAssertEqual(persisted, fixture.transfer)
            XCTAssertEqual(acceptedCount, 0)

            // The unauthorized attempt did not consume the pending revision.
            let approved = try await fixture.checker.decide(
                pending,
                decision: .approve
            )
            let countAfterApproval = await fixture.store.acceptedTransferCount

            XCTAssertEqual(approved.state, .approved)
            XCTAssertEqual(approved.revision, pending.revision + 1)
            XCTAssertEqual(countAfterApproval, 0)
        }
    }

    func test_sessionExpiringAfterApproval_blocksSubmissionAndPreservesIntent() async throws {
        let fixture = try await makeFixture()

        try await IntegrationFixtures.withJournal { storeURL, journal in
            let clock = ApprovalSessionClock()
            let credentials = ApprovalCredentialStore(
                credential: try SessionCredential(
                    identity: fixture.identity,
                    accessToken: "integration-session-only",
                    expiresAt: Date(timeIntervalSince1970: 200)
                )
            )

            let pending = try await fixture.maker.requestApproval(
                for: fixture.transfer.intent
            )
            let approved = try await fixture.checker.decide(
                pending,
                decision: .approve
            )

            await clock.set(Date(timeIntervalSince1970: 200))

            let approvedGateway = try fixture.maker.submissionGateway(
                for: approved
            )
            let submissions = IntegrationSubmissionSpy(
                underlying: approvedGateway
            )
            let authenticator = ApprovalStepUpSpy()
            let securedGateway = StepUpTransferGateway(
                sessions: SessionProvider(
                    store: credentials,
                    now: { await clock.now() }
                ),
                expectedIdentity: fixture.identity,
                authenticator: authenticator,
                underlying: submissions
            )
            let coordinator = TransferCoordinator(
                journal: journal,
                gateway: securedGateway,
                makeIdempotencyKey: {
                    fixture.transfer.idempotencyKey
                }
            )

            let state = try await coordinator.submit(
                fixture.transfer.intent
            )
            let failure = await coordinator.failure(
                for: fixture.transfer.intent.id
            )

            let reopenedJournal = try CoreDataTransferJournal(
                storeURL: storeURL
            )
            let persisted = try await reopenedJournal.entry(
                for: fixture.transfer.intent.id
            )
            let requests = await submissions.submissions
            let acceptedCount = await fixture.store.acceptedTransferCount

            XCTAssertEqual(approved.state, .approved)
            XCTAssertEqual(state, .unknown)
            XCTAssertEqual(failure, .authenticationRequired)
            XCTAssertEqual(persisted, fixture.transfer)
            XCTAssertEqual(authenticator.callCount, 0)
            XCTAssertTrue(requests.isEmpty)
            XCTAssertEqual(acceptedCount, 0)
        }
    }

    private func makeFixture() async throws -> ApprovalIntegrationFixture {
        let organizationID = IntegrationFixtures.organizationID
        let store = SimulatedTransferStore()
        let server = try SimulatedApprovalService(
            organizationID: organizationID,
            members: [
                BusinessContext(
                    organizationID: organizationID,
                    userID: IntegrationFixtures.makerID,
                    roles: [.maker]
                ),
                BusinessContext(
                    organizationID: organizationID,
                    userID: IntegrationFixtures.checkerID,
                    roles: [.checker]
                ),
                BusinessContext(
                    organizationID: organizationID,
                    userID: IntegrationFixtures.viewerID,
                    roles: [.viewer]
                ),
            ],
            store: store
        )

        let makerGateway = try await server.gateway(
            for: IntegrationFixtures.makerID
        )
        let checkerGateway = try await server.gateway(
            for: IntegrationFixtures.checkerID
        )
        let viewerGateway = try await server.gateway(
            for: IntegrationFixtures.viewerID
        )

        return ApprovalIntegrationFixture(
            transfer: try IntegrationFixtures.transfer(),
            identity: SessionIdentity(
                organizationID: organizationID,
                userID: IntegrationFixtures.makerID
            ),
            store: store,
            maker: TransferApprovalService(gateway: makerGateway),
            checker: TransferApprovalService(gateway: checkerGateway),
            viewer: viewerGateway
        )
    }
}

private struct ApprovalIntegrationFixture: Sendable {
    let transfer: JournaledTransfer
    let identity: SessionIdentity
    let store: SimulatedTransferStore
    let maker: TransferApprovalService
    let checker: TransferApprovalService
    let viewer: any ApprovalGateway
}

private actor ApprovalSessionClock {
    private var value = Date(timeIntervalSince1970: 100)

    func now() -> Date {
        value
    }

    func set(_ value: Date) {
        self.value = value
    }
}

private actor ApprovalCredentialStore: CredentialStore {
    private var credential: SessionCredential?

    init(credential: SessionCredential) {
        self.credential = credential
    }

    func load() async throws -> SessionCredential? {
        credential
    }

    func save(_ credential: SessionCredential) async throws {
        self.credential = credential
    }

    func delete() async throws {
        credential = nil
    }
}

@MainActor
private final class ApprovalStepUpSpy: StepUpAuthenticator {
    private(set) var callCount = 0

    func authenticate(reason: String) async throws {
        callCount += 1
    }
}
