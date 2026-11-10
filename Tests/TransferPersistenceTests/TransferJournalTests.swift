//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import XCTest
@testable import TransferPersistence

final class TransferJournalTests: XCTestCase {
    func testIntentAndKeySurviveJournalRecreation() async throws {
        let storeURL = try makeStoreURL()
        let expected = try makeEntry()

        try await persist(expected, at: storeURL)

        let reopened = try CoreDataTransferJournal(storeURL: storeURL)
        let restored = try await reopened.entry(for: expected.intent.id)

        XCTAssertEqual(restored, expected)
    }

    func testRepeatedIntentPreservesTheOriginalKey() async throws {
        let storeURL = try makeStoreURL()
        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let original = try makeEntry()
        let retry = try makeEntry(
            key: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        )

        _ = try await journal.record(
            original.intent,
            idempotencyKey: original.idempotencyKey
        )
        let repeated = try await journal.record(
            retry.intent,
            idempotencyKey: retry.idempotencyKey
        )

        XCTAssertEqual(repeated, original)
    }

    func testSameIdentityWithDifferentPayloadIsRejected() async throws {
        let storeURL = try makeStoreURL()
        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let original = try makeEntry()
        let changed = try makeEntry(minorUnits: 250_000)

        _ = try await journal.record(
            original.intent,
            idempotencyKey: original.idempotencyKey
        )

        do {
            _ = try await journal.record(
                changed.intent,
                idempotencyKey: changed.idempotencyKey
            )
            XCTFail("Expected an intent conflict.")
        } catch {
            XCTAssertEqual(error as? TransferJournalError, .intentConflict)
        }

        let stored = try await journal.entry(for: original.intent.id)
        XCTAssertEqual(stored, original)
    }

    func testSameKeyCannotBeAssignedToAnotherIntent() async throws {
        let storeURL = try makeStoreURL()
        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let original = try makeEntry()
        let other = try makeEntry(
            id: "22222222-2222-4222-8222-222222222222"
        )

        _ = try await journal.record(
            original.intent,
            idempotencyKey: original.idempotencyKey
        )

        do {
            _ = try await journal.record(
                other.intent,
                idempotencyKey: other.idempotencyKey
            )
            XCTFail("Expected an idempotency key conflict.")
        } catch {
            XCTAssertEqual(
                error as? TransferJournalError,
                .idempotencyKeyConflict
            )
        }

        let stored = try await journal.entry(for: original.intent.id)
        let rejected = try await journal.entry(for: other.intent.id)

        XCTAssertEqual(stored, original)
        XCTAssertNil(rejected)
    }

    func testFailedSaveDoesNotPersistTheNewIntent() async throws {
        let storeURL = try makeStoreURL()
        let original = try makeEntry()
        let attempted = try makeEntry(
            id: "22222222-2222-4222-8222-222222222222",
            key: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        )
        try await persist(original, at: storeURL)

        let readOnly = try CoreDataTransferJournal(
            storeURL: storeURL,
            readOnly: true
        )

        do {
            _ = try await readOnly.record(
                attempted.intent,
                idempotencyKey: attempted.idempotencyKey
            )
            XCTFail("Expected a storage failure.")
        } catch {
            XCTAssertEqual(error as? TransferJournalError, .storageFailure)
        }

        let reopened = try CoreDataTransferJournal(storeURL: storeURL)
        let missing = try await reopened.entry(for: attempted.intent.id)
        let preserved = try await reopened.entry(for: original.intent.id)

        XCTAssertNil(missing)
        XCTAssertEqual(preserved, original)
    }

    func testConcurrentWritersConvergeOnOneStoredKey() async throws {
        let storeURL = try makeStoreURL()
        let firstJournal = try CoreDataTransferJournal(storeURL: storeURL)
        let secondJournal = try CoreDataTransferJournal(storeURL: storeURL)
        let firstProposal = try makeEntry()
        let secondProposal = try makeEntry(
            key: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        )

        async let first = firstJournal.record(
            firstProposal.intent,
            idempotencyKey: firstProposal.idempotencyKey
        )
        async let second = secondJournal.record(
            secondProposal.intent,
            idempotencyKey: secondProposal.idempotencyKey
        )

        let (firstResult, secondResult) = try await (first, second)

        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(firstResult.intent, firstProposal.intent)
        XCTAssertTrue(
            [
                firstProposal.idempotencyKey,
                secondProposal.idempotencyKey
            ].contains(firstResult.idempotencyKey)
        )

        let reopened = try CoreDataTransferJournal(storeURL: storeURL)
        let stored = try await reopened.entry(for: firstProposal.intent.id)

        XCTAssertEqual(stored, firstResult)
    }

    private func makeEntry(
        id: String = "11111111-1111-4111-8111-111111111111",
        key: String = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
        minorUnits: Int64 = 125_050
    ) throws -> JournaledTransfer {
        let intentID = try XCTUnwrap(UUID(uuidString: id))
        let idempotencyKey = try XCTUnwrap(UUID(uuidString: key))
        let amount = try Money(
            minorUnits: minorUnits,
            currencyCode: "IDR",
            scale: 2
        )

        return JournaledTransfer(
            intent: TransferIntent(id: intentID, amount: amount),
            idempotencyKey: idempotencyKey
        )
    }

    private func persist(
        _ entry: JournaledTransfer,
        at storeURL: URL
    ) async throws {
        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        _ = try await journal.record(
            entry.intent,
            idempotencyKey: entry.idempotencyKey
        )
    }

    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }

        return directory.appendingPathComponent("journal.sqlite")
    }
}
