//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferPersistence
import TransferSimulation
import XCTest

@MainActor
final class TransferApprovalTests: XCTestCase {
    func testMakerCannotApproveOwnRequestEvenWithForgedSnapshot() async throws {
        let fixture = try await makeFixture()
        let request = try await fixture.maker.requestApproval(
            for: fixture.transfer.intent
        )
        let forged = ApprovalRequest(
            id: request.id,
            organizationID: request.organizationID,
            makerID: fixture.checkerID,
            intent: request.intent,
            state: .pending,
            revision: request.revision
        )

        for snapshot in [request, forged] {
            await assertApprovalError(.selfApproval) {
                _ = try await fixture.maker.decide(
                    snapshot,
                    decision: .approve
                )
            }
        }
    }

    func testUnauthorizedRoleCannotCreateOrDecideApproval() async throws {
        let fixture = try await makeFixture()
        let request = try await fixture.maker.requestApproval(
            for: fixture.transfer.intent
        )

        await assertApprovalError(.unauthorized) {
            _ = try await fixture.viewerGateway.createRequest(
                for: fixture.transfer.intent
            )
        }

        await assertApprovalError(.unauthorized) {
            _ = try await fixture.viewerGateway.decide(
                approvalID: request.id,
                expectedRevision: request.revision,
                decision: .approve
            )
        }
    }

    func testApprovedSubmissionUsesCoordinatorAndDurableJournal() async throws {
        let fixture = try await makeFixture()
        let request = try await fixture.maker.requestApproval(
            for: fixture.transfer.intent
        )
        let approved = try await fixture.checker.decide(
            request,
            decision: .approve
        )
        let storeURL = try makeStoreURL()
        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let gateway = try fixture.maker.submissionGateway(for: approved)
        let key = fixture.transfer.idempotencyKey
        let coordinator = TransferCoordinator(
            journal: journal,
            gateway: gateway,
            makeIdempotencyKey: { key }
        )

        let firstState = try await coordinator.submit(
            fixture.transfer.intent
        )
        let repeatedState = try await coordinator.submit(
            fixture.transfer.intent
        )
        let journaled = try await journal.entry(
            for: fixture.transfer.intent.id
        )
        let accepted = await fixture.store.acceptedTransfer(for: key)
        let count = await fixture.store.acceptedTransferCount

        XCTAssertEqual(approved.state, .approved)
        XCTAssertEqual(approved.revision, 2)
        XCTAssertEqual(approved.decidedBy, fixture.checkerID)
        XCTAssertEqual(firstState, .accepted)
        XCTAssertEqual(repeatedState, .accepted)
        XCTAssertEqual(journaled, fixture.transfer)
        XCTAssertEqual(accepted, fixture.transfer)
        XCTAssertEqual(count, 1)
    }

    func testForgedApprovedSnapshotCannotSubmitPendingOrRejectedRequest() async throws {
        let fixture = try await makeFixture()
        let pending = try await fixture.maker.requestApproval(
            for: fixture.transfer.intent
        )
        let forgedPending = claimingApproved(pending)
        let pendingGateway = try fixture.maker.submissionGateway(
            for: forgedPending
        )

        await assertApprovalError(.approvalRequired) {
            _ = try await pendingGateway.submit(fixture.transfer)
        }

        let rejected = try await fixture.checker.decide(
            pending,
            decision: .reject
        )
        let forgedRejected = claimingApproved(rejected)
        let rejectedGateway = try fixture.maker.submissionGateway(
            for: forgedRejected
        )

        await assertApprovalError(.approvalRejected) {
            _ = try await rejectedGateway.submit(fixture.transfer)
        }

        let count = await fixture.store.acceptedTransferCount
        XCTAssertEqual(count, 0)
    }

    func testStaleRevisionCannotDecideOrSubmit() async throws {
        let fixture = try await makeFixture()
        let original = try await fixture.maker.requestApproval(
            for: fixture.transfer.intent
        )
        let approved = try await fixture.checker.decide(
            original,
            decision: .approve
        )

        await assertApprovalError(.staleRevision) {
            _ = try await fixture.checker.decide(
                original,
                decision: .reject
            )
        }

        let staleGateway = try fixture.maker.submissionGateway(
            for: claimingApproved(original)
        )

        await assertApprovalError(.staleRevision) {
            _ = try await staleGateway.submit(fixture.transfer)
        }

        let countBeforeValidSubmission = await fixture.store.acceptedTransferCount
        XCTAssertEqual(countBeforeValidSubmission, 0)

        let validGateway = try fixture.maker.submissionGateway(for: approved)
        let result = try await validGateway.submit(fixture.transfer)

        XCTAssertEqual(result, .accepted)
    }

    func testApprovalCannotAuthorizeChangedPayload() async throws {
        let fixture = try await makeFixture()
        let request = try await fixture.maker.requestApproval(
            for: fixture.transfer.intent
        )
        let approved = try await fixture.checker.decide(
            request,
            decision: .approve
        )
        let changedAmount = try Money(
            minorUnits: 250_000,
            currencyCode: "IDR",
            scale: 2
        )
        let changedTransfer = JournaledTransfer(
            intent: TransferIntent(
                id: fixture.transfer.intent.id,
                amount: changedAmount
            ),
            idempotencyKey: fixture.transfer.idempotencyKey
        )
        let gateway = try fixture.maker.submissionGateway(for: approved)

        await assertApprovalError(.intentConflict) {
            _ = try await gateway.submit(changedTransfer)
        }

        let count = await fixture.store.acceptedTransferCount
        XCTAssertEqual(count, 0)
    }

    func testAnotherOrganizationCannotDecideRequest() async throws {
        let fixture = try await makeFixture()
        let request = try await fixture.maker.requestApproval(
            for: fixture.transfer.intent
        )
        let otherOrganization = try uuid(
            "88888888-8888-8888-8888-888888888888"
        )
        let otherServer = try SimulatedApprovalService(
            organizationID: otherOrganization,
            members: [
                BusinessContext(
                    organizationID: otherOrganization,
                    userID: fixture.checkerID,
                    roles: [.checker]
                )
            ]
        )
        let otherGateway = try await otherServer.gateway(
            for: fixture.checkerID
        )

        await assertApprovalError(.requestNotFound) {
            _ = try await otherGateway.decide(
                approvalID: request.id,
                expectedRevision: request.revision,
                decision: .approve
            )
        }
    }

    func testConcurrentDecisionsAllowOnlyOneRevisionChange() async throws {
        let fixture = try await makeFixture()
        let request = try await fixture.maker.requestApproval(
            for: fixture.transfer.intent
        )

        async let approval = decisionOutcome(
            gateway: fixture.checkerGateway,
            request: request,
            decision: .approve
        )
        async let rejection = decisionOutcome(
            gateway: fixture.checkerGateway,
            request: request,
            decision: .reject
        )

        let outcomes = await [approval, rejection]
        let successes = outcomes.compactMap { outcome -> ApprovalRequest? in
            if case let .success(request) = outcome {
                return request
            }
            return nil
        }
        let staleFailures = outcomes.filter { outcome in
            if case .failure(.staleRevision) = outcome {
                return true
            }
            return false
        }

        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(successes.first?.revision, 2)
        XCTAssertEqual(staleFailures.count, 1)
    }

    private func claimingApproved(
        _ request: ApprovalRequest
    ) -> ApprovalRequest {
        ApprovalRequest(
            id: request.id,
            organizationID: request.organizationID,
            makerID: request.makerID,
            intent: request.intent,
            state: .approved,
            revision: request.revision,
            decidedBy: request.decidedBy
        )
    }

    private func makeFixture() async throws -> ApprovalFixture {
        let organizationID = try uuid(
            "33333333-3333-3333-3333-333333333333"
        )
        let makerID = try uuid(
            "44444444-4444-4444-4444-444444444444"
        )
        let checkerID = try uuid(
            "55555555-5555-5555-5555-555555555555"
        )
        let viewerID = try uuid(
            "66666666-6666-6666-6666-666666666666"
        )
        let approvalID = try uuid(
            "77777777-7777-7777-7777-777777777777"
        )
        let transfer = JournaledTransfer(
            intent: TransferIntent(
                id: try uuid("11111111-1111-1111-1111-111111111111"),
                amount: try Money(
                    minorUnits: 125_000,
                    currencyCode: "IDR",
                    scale: 2
                )
            ),
            idempotencyKey: try uuid(
                "22222222-2222-2222-2222-222222222222"
            )
        )
        let store = SimulatedTransferStore()
        let server = try SimulatedApprovalService(
            organizationID: organizationID,
            members: [
                BusinessContext(
                    organizationID: organizationID,
                    userID: makerID,
                    roles: [.maker, .checker]
                ),
                BusinessContext(
                    organizationID: organizationID,
                    userID: checkerID,
                    roles: [.checker]
                ),
                BusinessContext(
                    organizationID: organizationID,
                    userID: viewerID,
                    roles: [.viewer]
                ),
            ],
            store: store,
            makeApprovalID: { approvalID }
        )
        let makerGateway = try await server.gateway(for: makerID)
        let checkerGateway = try await server.gateway(for: checkerID)
        let viewerGateway = try await server.gateway(for: viewerID)

        return ApprovalFixture(
            store: store,
            transfer: transfer,
            checkerID: checkerID,
            maker: TransferApprovalService(gateway: makerGateway),
            checker: TransferApprovalService(gateway: checkerGateway),
            checkerGateway: checkerGateway,
            viewerGateway: viewerGateway
        )
    }

    private func uuid(_ value: String) throws -> UUID {
        try XCTUnwrap(UUID(uuidString: value))
    }

    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TransferApprovalTests-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }

        return directory.appendingPathComponent("journal.sqlite")
    }

    private func assertApprovalError(
        _ expected: ApprovalError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected an approval error.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? ApprovalError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private struct ApprovalFixture {
    let store: SimulatedTransferStore
    let transfer: JournaledTransfer
    let checkerID: UUID
    let maker: TransferApprovalService
    let checker: TransferApprovalService
    let checkerGateway: any ApprovalGateway
    let viewerGateway: any ApprovalGateway
}

private enum DecisionOutcome: Sendable {
    case success(ApprovalRequest)
    case failure(ApprovalError)
    case unexpectedFailure
}

private func decisionOutcome(
    gateway: any ApprovalGateway,
    request: ApprovalRequest,
    decision: ApprovalDecision
) async -> DecisionOutcome {
    do {
        let result = try await gateway.decide(
            approvalID: request.id,
            expectedRevision: request.revision,
            decision: decision
        )
        return .success(result)
    } catch let error as ApprovalError {
        return .failure(error)
    } catch {
        return .unexpectedFailure
    }
}
