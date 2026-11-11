//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDemoSupport
import TransferDomain
import TransferPersistence
import TransferSecurity
import XCTest

@MainActor
final class BusinessTransferWorkflowTests: XCTestCase {
    func test_approvedTransfer_reachesAuthoritativeSettlement() async throws {
        try await withDemo { demo, _ in
            try await demo.requestApproval(amount: self.makeAmount())
            XCTAssertEqual(demo.approval?.state, .pending)

            try await demo.decide(.approve)
            XCTAssertEqual(demo.approval?.state, .approved)

            try await demo.submit()
            XCTAssertEqual(demo.state, .accepted)

            try await demo.simulateSettlement()

            XCTAssertEqual(demo.state, .settled)

            let recovered = try XCTUnwrap(demo.recoveredTransfers.first)
            XCTAssertEqual(
                recovered.reconciliation,
                .confirmed(state: .settled, attempts: 1)
            )
            XCTAssertEqual(recovered.classification, .completed)
        }
    }

    func test_lostResponse_recoversAfterClientRecreationWithOriginalIdentity() async throws {
        try await withDemo { demo, storeURL in
            try await demo.requestApproval(amount: self.makeAmount())
            try await demo.decide(.approve)
            try await demo.submit(loseResponse: true)

            XCTAssertEqual(demo.state, .unknown)

            let intent = try XCTUnwrap(demo.approval?.intent)
            let journal = try CoreDataTransferJournal(storeURL: storeURL)
            let stored = try await journal.entry(for: intent.id)
            let original = try XCTUnwrap(stored)

            try await demo.recreateClientAndRecover()

            XCTAssertEqual(demo.state, .accepted)
            XCTAssertEqual(demo.recoveredTransfers.count, 1)

            let recovered = try XCTUnwrap(demo.recoveredTransfers.first)
            XCTAssertEqual(recovered.entry, original)
            XCTAssertEqual(
                recovered.reconciliation,
                .confirmed(state: .accepted, attempts: 1)
            )
        }
    }

    func test_rejectedApproval_preventsSubmissionAndJournalCreation() async throws {
        try await withDemo { demo, storeURL in
            try await demo.requestApproval(amount: self.makeAmount())
            try await demo.decide(.reject)

            XCTAssertEqual(demo.approval?.state, .rejected)

            do {
                try await demo.submit()
                XCTFail("Expected rejected approval to block submission.")
            } catch {
                XCTAssertEqual(
                    error as? DemoDependencies.Failure,
                    .invalidStep
                )
            }

            let journal = try CoreDataTransferJournal(storeURL: storeURL)
            let entries = try await journal.allEntries()

            XCTAssertTrue(entries.isEmpty)
            XCTAssertNil(demo.state)
        }
    }

    private func makeAmount() throws -> Money {
        try Money(
            minorUnits: 10_000_000,
            currencyCode: "IDR",
            scale: 2
        )
    }

    private func withDemo(
        _ operation: @MainActor (DemoDependencies, URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL = directory.appendingPathComponent("journal.sqlite")
        let demo = try DemoDependencies(
            storeURL: storeURL,
            credentials: WorkflowCredentialStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        try await operation(demo, storeURL)
    }
}

private actor WorkflowCredentialStore: CredentialStore {
    private var credential: SessionCredential?

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
