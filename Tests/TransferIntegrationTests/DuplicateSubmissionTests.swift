//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferSimulation
import XCTest

@MainActor
final class DuplicateSubmissionTests: XCTestCase {
    func test_duplicateWhileAcceptedResponseIsHeld_doesNotSubmitAgain() async throws {
        try await IntegrationFixtures.withJournal { _, journal in
            let transfer = try IntegrationFixtures.transfer()
            let entered = XCTestExpectation(
                description: "Bank accepted and is holding its response"
            )
            let release = SubmissionResponseGate()
            let store = SimulatedTransferStore()
            let bank = SimulatedBank(
                store: store,
                faults: [
                    transfer.idempotencyKey: .delayedResponse {
                        entered.fulfill()
                        await release.wait()
                    },
                ]
            )
            let gateway = IntegrationSubmissionSpy(underlying: bank)
            let coordinator = TransferCoordinator(
                journal: journal,
                gateway: gateway,
                makeIdempotencyKey: { transfer.idempotencyKey }
            )

            let firstSubmission = Task {
                try await coordinator.submit(transfer.intent)
            }

            let waitResult = await XCTWaiter.fulfillment(
                of: [entered],
                timeout: 5
            )

            guard waitResult == .completed else {
                await release.open()
                firstSubmission.cancel()
                _ = await firstSubmission.result
                XCTFail("The bank did not reach the controlled response boundary.")
                return
            }

            do {
                let duplicateState = try await coordinator.submit(
                    transfer.intent
                )
                let persisted = try await journal.entry(
                    for: transfer.intent.id
                )
                let requestsWhileHeld = await gateway.submissions
                let acceptedWhileHeld = await store.acceptedTransferCount

                XCTAssertEqual(duplicateState, .submitting)
                XCTAssertEqual(persisted, transfer)
                XCTAssertEqual(requestsWhileHeld, [transfer])
                XCTAssertEqual(acceptedWhileHeld, 1)

                await release.open()

                let firstState = try await firstSubmission.value
                let repeatedState = try await coordinator.submit(
                    transfer.intent
                )
                let finalRequests = await gateway.submissions
                let finalCount = await store.acceptedTransferCount

                XCTAssertEqual(firstState, .accepted)
                XCTAssertEqual(repeatedState, .accepted)
                XCTAssertEqual(finalRequests, [transfer])
                XCTAssertEqual(finalCount, 1)
            } catch {
                await release.open()
                firstSubmission.cancel()
                _ = await firstSubmission.result
                throw error
            }
        }
    }
}

private actor SubmissionResponseGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()

        for continuation in pending {
            continuation.resume()
        }
    }
}
