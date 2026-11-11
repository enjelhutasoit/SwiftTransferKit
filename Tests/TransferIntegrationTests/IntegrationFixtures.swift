//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferPersistence

enum IntegrationFixtures {
    // Fixed identifiers are test data, isolated by a temporary store per test.
    static let intentID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000001"
    )!
    static let key = UUID(
        uuidString: "00000000-0000-4000-8000-000000000002"
    )!
    static let organizationID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000003"
    )!
    static let makerID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000004"
    )!
    static let checkerID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000005"
    )!
    static let viewerID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000006"
    )!

    static func transfer() throws -> JournaledTransfer {
        JournaledTransfer(
            intent: TransferIntent(
                id: intentID,
                amount: try Money(
                    minorUnits: 10_000_000,
                    currencyCode: "IDR",
                    scale: 2
                )
            ),
            idempotencyKey: key
        )
    }

    @MainActor
    static func withJournal(
        _ operation: @MainActor (
            URL,
            CoreDataTransferJournal
        ) async throws -> Void
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
        let journal = try CoreDataTransferJournal(storeURL: storeURL)

        try await operation(storeURL, journal)
    }
}

actor IntegrationSubmissionSpy: TransferGateway {
    private let underlying: any TransferGateway
    private(set) var submissions: [JournaledTransfer] = []

    init(underlying: any TransferGateway) {
        self.underlying = underlying
    }

    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        submissions.append(transfer)
        return try await underlying.submit(transfer)
    }
}
