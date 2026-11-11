//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import XCTest

@MainActor
final class TransferDiagnosticsTests: XCTestCase {
    func test_repeatedSubmission_preservesCorrelationWithoutResubmission() async throws {
        let intent = try makeIntent()
        let diagnostics = DiagnosticsSpy()
        let gateway = DiagnosticsGatewaySpy(result: .success(.accepted))
        let coordinator = makeCoordinator(
            journal: DiagnosticsJournalFake(),
            gateway: gateway,
            diagnostics: diagnostics
        )

        let firstState = try await coordinator.submit(intent)
        let repeatedState = try await coordinator.submit(intent)
        let callCount = await gateway.callCount
        let events = diagnostics.events

        XCTAssertEqual(firstState, .accepted)
        XCTAssertEqual(repeatedState, .accepted)
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(
            events.map(\.name),
            [
                .submissionStarted,
                .intentJournaled,
                .submissionAccepted,
                .submissionReused,
            ]
        )
        XCTAssertEqual(
            events.map(\.correlationID),
            Array(repeating: DiagnosticFixtures.correlationID, count: 4)
        )
    }

    func test_failureEvents_excludeSensitivePayloadAndRawError() async throws {
        let intent = try makeIntent()
        let secret = "sensitive-test-token"
        let account = "account-9988776655"
        let diagnostics = DiagnosticsSpy()
        let gateway = DiagnosticsGatewaySpy(
            result: .failure(
                SensitiveDiagnosticFailure(
                    description: "token=\(secret) account=\(account)"
                )
            )
        )
        let coordinator = makeCoordinator(
            journal: DiagnosticsJournalFake(),
            gateway: gateway,
            diagnostics: diagnostics
        )

        let state = try await coordinator.submit(intent)
        let events = diagnostics.events

        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(
            events.map(\.name),
            [
                .submissionStarted,
                .intentJournaled,
                .submissionUnresolved,
            ]
        )

        let forbiddenValues = [
            secret,
            account,
            intent.id.uuidString,
            DiagnosticFixtures.idempotencyKey.uuidString,
            String(intent.amount.minorUnits),
        ]

        for event in events {
            let data = try JSONEncoder().encode(event)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )

            // This is the public diagnostic payload allowlist.
            XCTAssertEqual(
                Set(object.keys),
                Set(["name", "correlationID"])
            )

            let representations = [
                String(decoding: data, as: UTF8.self),
                String(reflecting: event),
            ]

            for representation in representations {
                for forbiddenValue in forbiddenValues {
                    XCTAssertFalse(
                        representation.lowercased().contains(
                            forbiddenValue.lowercased()
                        )
                    )
                }
            }
        }
    }

    func test_throwingDiagnostics_doNotChangeSubmissionResults() async throws {
        let cases: [
            (
                Result<TransferSubmissionResult, any Error>,
                TransferState,
                TransferFailure?
            )
        ] = [
            (.success(.accepted), .accepted, nil),
            (.success(.rejected), .rejected, nil),
            (
                .failure(TransferFailure.transportFailure),
                .unknown,
                .transportFailure
            ),
        ]

        for (result, expectedState, expectedFailure) in cases {
            let intent = try makeIntent()
            let journal = DiagnosticsJournalFake()
            let diagnostics = DiagnosticsSpy(shouldThrow: true)
            let gateway = DiagnosticsGatewaySpy(result: result)
            let coordinator = makeCoordinator(
                journal: journal,
                gateway: gateway,
                diagnostics: diagnostics
            )

            let state = try await coordinator.submit(intent)
            let failure = await coordinator.failure(for: intent.id)
            let persisted = try await journal.entry(for: intent.id)
            let callCount = await gateway.callCount

            XCTAssertEqual(state, expectedState)
            XCTAssertEqual(failure, expectedFailure)
            XCTAssertEqual(persisted?.intent, intent)
            XCTAssertEqual(
                persisted?.idempotencyKey,
                DiagnosticFixtures.idempotencyKey
            )
            XCTAssertEqual(callCount, 1)
            XCTAssertEqual(diagnostics.events.count, 3)
        }
    }

    func test_persistenceFailure_isPreservedWhenDiagnosticsAlsoFail() async throws {
        let diagnostics = DiagnosticsSpy(shouldThrow: true)
        let gateway = DiagnosticsGatewaySpy(result: .success(.accepted))
        let coordinator = makeCoordinator(
            journal: DiagnosticsJournalFake(failsToRecord: true),
            gateway: gateway,
            diagnostics: diagnostics
        )

        do {
            _ = try await coordinator.submit(makeIntent())
            XCTFail("Expected persistence failure.")
        } catch {
            XCTAssertEqual(
                error as? TransferOperationError,
                .persistenceFailure
            )
        }

        let callCount = await gateway.callCount

        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(
            diagnostics.events.map(\.name),
            [.submissionStarted, .preparationFailed]
        )
    }

    func test_existingIntent_emitsReconciliationRequiredWithoutSubmission() async throws {
        let intent = try makeIntent()
        let entry = JournaledTransfer(
            intent: intent,
            idempotencyKey: DiagnosticFixtures.idempotencyKey
        )
        let diagnostics = DiagnosticsSpy()
        let gateway = DiagnosticsGatewaySpy(result: .success(.accepted))
        let coordinator = makeCoordinator(
            journal: DiagnosticsJournalFake(existing: entry),
            gateway: gateway,
            diagnostics: diagnostics
        )

        let state = try await coordinator.submit(intent)
        let callCount = await gateway.callCount

        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(
            diagnostics.events.map(\.name),
            [.submissionStarted, .reconciliationRequired]
        )
    }

    private func makeIntent() throws -> TransferIntent {
        TransferIntent(
            id: DiagnosticFixtures.intentID,
            amount: try Money(
                minorUnits: 123_456_789,
                currencyCode: "IDR",
                scale: 2
            )
        )
    }

    private func makeCoordinator(
        journal: DiagnosticsJournalFake,
        gateway: DiagnosticsGatewaySpy,
        diagnostics: DiagnosticsSpy
    ) -> TransferCoordinator {
        TransferCoordinator(
            journal: journal,
            gateway: gateway,
            diagnostics: diagnostics,
            makeCorrelationID: { DiagnosticFixtures.correlationID },
            makeIdempotencyKey: { DiagnosticFixtures.idempotencyKey }
        )
    }
}

private enum DiagnosticFixtures {
    static let intentID = UUID(
        uuidString: "11111111-1111-4111-8111-111111111111"
    )!
    static let idempotencyKey = UUID(
        uuidString: "22222222-2222-4222-8222-222222222222"
    )!
    static let correlationID = UUID(
        uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    )!
}

private struct SensitiveDiagnosticFailure: Error, CustomStringConvertible {
    let description: String
}

private enum DiagnosticSinkFailure: Error {
    case unavailable
}

/// Every access to mutable storage is protected by the same lock.
private final class DiagnosticsSpy: TransferDiagnostics, @unchecked Sendable {
    private let lock = NSLock()
    private let shouldThrow: Bool
    private var storage: [TransferDiagnosticEvent] = []

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    var events: [TransferDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: TransferDiagnosticEvent) throws {
        lock.lock()
        defer { lock.unlock() }

        storage.append(event)

        if shouldThrow {
            throw DiagnosticSinkFailure.unavailable
        }
    }
}

private actor DiagnosticsGatewaySpy: TransferGateway {
    private let result: Result<TransferSubmissionResult, any Error>
    private(set) var callCount = 0

    init(result: Result<TransferSubmissionResult, any Error>) {
        self.result = result
    }

    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        callCount += 1
        return try result.get()
    }
}

private actor DiagnosticsJournalFake: TransferJournal {
    private let failsToRecord: Bool
    private var stored: JournaledTransfer?

    init(
        existing: JournaledTransfer? = nil,
        failsToRecord: Bool = false
    ) {
        stored = existing
        self.failsToRecord = failsToRecord
    }

    func record(
        _ intent: TransferIntent,
        idempotencyKey: UUID
    ) async throws -> JournaledTransfer {
        if failsToRecord {
            throw TransferJournalError.storageFailure
        }

        if let stored {
            guard stored.intent == intent else {
                throw TransferJournalError.intentConflict
            }
            return stored
        }

        let entry = JournaledTransfer(
            intent: intent,
            idempotencyKey: idempotencyKey
        )
        stored = entry
        return entry
    }

    func entry(for intentID: UUID) async throws -> JournaledTransfer? {
        guard stored?.intent.id == intentID else {
            return nil
        }
        return stored
    }
}
