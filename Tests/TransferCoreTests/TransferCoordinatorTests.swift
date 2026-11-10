//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import XCTest

@MainActor
final class TransferCoordinatorTests: XCTestCase {
    func testSubmitUsesJournalReturnedKeyAfterPersistence() async throws {
        let intent = try makeIntent()
        let storedKey = try XCTUnwrap(
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")
        )
        let winningEntry = JournaledTransfer(
            intent: intent,
            idempotencyKey: storedKey
        )
        let journal = TransferJournalFake(
            entryAppearingDuringRecord: winningEntry
        )
        let gateway = TransferGatewaySpy(journal: journal)
        let coordinator = try makeCoordinator(
            journal: journal,
            gateway: gateway
        )

        let state = try await coordinator.submit(intent)

        XCTAssertEqual(state, .accepted)

        let observations = await gateway.observations
        XCTAssertEqual(observations.count, 1)

        let observation = try XCTUnwrap(observations.first)
        XCTAssertEqual(observation.received, winningEntry)
        XCTAssertEqual(observation.persistedAtSubmission, winningEntry)
    }

    func testConcurrentDuplicateDuringSaveDoesNotSendAgain() async throws {
        let intent = try makeIntent()
        let gate = AsyncGate()
        let journal = TransferJournalFake(recordGate: gate)
        let gateway = TransferGatewaySpy(journal: journal)
        let coordinator = try makeCoordinator(
            journal: journal,
            gateway: gateway
        )

        addTeardownBlock {
            await gate.open()
        }

        let firstSubmission = Task {
            try await coordinator.submit(intent)
        }

        await gate.waitUntilEntered()

        let duplicateState = try await coordinator.submit(intent)
        let requestsBeforeSave = await gateway.observations
        let recordCallsBeforeSave = await journal.recordCalls

        XCTAssertEqual(duplicateState, .submitting)
        XCTAssertTrue(requestsBeforeSave.isEmpty)
        XCTAssertEqual(recordCallsBeforeSave, 1)

        await gate.open()

        let firstState = try await firstSubmission.value
        let repeatedState = try await coordinator.submit(intent)
        let observations = await gateway.observations
        let recordCalls = await journal.recordCalls

        XCTAssertEqual(firstState, .accepted)
        XCTAssertEqual(repeatedState, .accepted)
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(recordCalls, 1)
    }

    func testSaveFailurePreventsSendAndAllowsRetryAfterStorageRecovers() async throws {
        let intent = try makeIntent()
        let journal = TransferJournalFake(recordFailure: .storageFailure)
        let gateway = TransferGatewaySpy(journal: journal)
        let coordinator = try makeCoordinator(
            journal: journal,
            gateway: gateway
        )

        await assertOperationError(
            .persistenceFailure,
            coordinator: coordinator,
            intent: intent
        )

        let observationsAfterFailure = await gateway.observations
        let stateAfterFailure = await coordinator.state(for: intent.id)

        XCTAssertTrue(observationsAfterFailure.isEmpty)
        XCTAssertNil(stateAfterFailure)

        await journal.setRecordFailure(nil)

        let recoveredState = try await coordinator.submit(intent)
        let observationsAfterRecovery = await gateway.observations

        XCTAssertEqual(recoveredState, .accepted)
        XCTAssertEqual(observationsAfterRecovery.count, 1)
    }

    func testReadFailurePreventsRecordingAndSending() async throws {
        let intent = try makeIntent()
        let journal = TransferJournalFake(readFailure: .storageFailure)
        let gateway = TransferGatewaySpy(journal: journal)
        let coordinator = try makeCoordinator(
            journal: journal,
            gateway: gateway
        )

        await assertOperationError(
            .persistenceFailure,
            coordinator: coordinator,
            intent: intent
        )

        let recordCalls = await journal.recordCalls
        let observations = await gateway.observations

        XCTAssertEqual(recordCalls, 0)
        XCTAssertTrue(observations.isEmpty)
    }

    func testUnknownOutcomePreservesIdentityAcrossCoordinatorRecreation() async throws {
        let intent = try makeIntent()
        let journal = TransferJournalFake()
        let gateway = TransferGatewaySpy(
            journal: journal,
            result: .failure(.responseLost)
        )
        let coordinator = try makeCoordinator(
            journal: journal,
            gateway: gateway
        )

        let firstState = try await coordinator.submit(intent)
        let originalEntry = try await journal.entry(for: intent.id)
        let repeatedState = try await coordinator.submit(intent)

        let differentCandidateKey = try XCTUnwrap(
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")
        )
        let recreatedCoordinator = TransferCoordinator(
            journal: journal,
            gateway: gateway,
            makeIdempotencyKey: { differentCandidateKey }
        )

        let restoredState = try await recreatedCoordinator.submit(intent)
        let preservedEntry = try await journal.entry(for: intent.id)
        let observations = await gateway.observations
        let recordCalls = await journal.recordCalls

        XCTAssertEqual(firstState, .unknown)
        XCTAssertEqual(repeatedState, .unknown)
        XCTAssertEqual(restoredState, .unknown)
        XCTAssertNotNil(originalEntry)
        XCTAssertEqual(preservedEntry, originalEntry)
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(recordCalls, 1)
    }

    func testExplicitRejectionIsRetainedWithoutResubmission() async throws {
        let intent = try makeIntent()
        let journal = TransferJournalFake()
        let gateway = TransferGatewaySpy(
            journal: journal,
            result: .success(.rejected)
        )
        let coordinator = try makeCoordinator(
            journal: journal,
            gateway: gateway
        )

        let firstState = try await coordinator.submit(intent)
        let repeatedState = try await coordinator.submit(intent)
        let observations = await gateway.observations

        XCTAssertEqual(firstState, .rejected)
        XCTAssertEqual(repeatedState, .rejected)
        XCTAssertEqual(observations.count, 1)
    }

    func testConflictingPayloadCannotReplaceInFlightIntent() async throws {
        let intent = try makeIntent()
        let changedIntent = try makeIntent(minorUnits: 250_000)
        let gate = AsyncGate()
        let journal = TransferJournalFake()
        let gateway = TransferGatewaySpy(
            journal: journal,
            submissionGate: gate
        )
        let coordinator = try makeCoordinator(
            journal: journal,
            gateway: gateway
        )

        addTeardownBlock {
            await gate.open()
        }

        let firstSubmission = Task {
            try await coordinator.submit(intent)
        }

        await gate.waitUntilEntered()

        await assertOperationError(
            .intentConflict,
            coordinator: coordinator,
            intent: changedIntent
        )

        await gate.open()

        let state = try await firstSubmission.value
        let observations = await gateway.observations

        XCTAssertEqual(state, .accepted)
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations.first?.received.intent, intent)
    }

    func testConflictingPersistedPayloadIsRejectedWithoutSending() async throws {
        let originalIntent = try makeIntent()
        let changedIntent = try makeIntent(minorUnits: 250_000)
        let key = try XCTUnwrap(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let journal = TransferJournalFake(
            existingEntry: JournaledTransfer(
                intent: originalIntent,
                idempotencyKey: key
            )
        )
        let gateway = TransferGatewaySpy(journal: journal)
        let coordinator = try makeCoordinator(
            journal: journal,
            gateway: gateway
        )

        await assertOperationError(
            .intentConflict,
            coordinator: coordinator,
            intent: changedIntent
        )

        let recordCalls = await journal.recordCalls
        let observations = await gateway.observations
        let preservedEntry = try await journal.entry(for: originalIntent.id)

        XCTAssertEqual(recordCalls, 0)
        XCTAssertTrue(observations.isEmpty)
        XCTAssertEqual(preservedEntry?.intent, originalIntent)
    }

    private func makeIntent(
        minorUnits: Int64 = 125_000
    ) throws -> TransferIntent {
        let id = try XCTUnwrap(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let amount = try Money(
            minorUnits: minorUnits,
            currencyCode: "IDR",
            scale: 2
        )

        return TransferIntent(id: id, amount: amount)
    }

    private func makeCoordinator(
        journal: any TransferJournal,
        gateway: any TransferGateway
    ) throws -> TransferCoordinator {
        let key = try XCTUnwrap(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )

        return TransferCoordinator(
            journal: journal,
            gateway: gateway,
            makeIdempotencyKey: { key }
        )
    }

    private func assertOperationError(
        _ expected: TransferOperationError,
        coordinator: TransferCoordinator,
        intent: TransferIntent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await coordinator.submit(intent)
            XCTFail("Expected submission to throw.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? TransferOperationError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var hasEntered = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        hasEntered = true

        let pendingObservers = observers
        observers.removeAll()

        for observer in pendingObservers {
            observer.resume()
        }

        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            blocked.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else {
            return
        }

        await withCheckedContinuation { continuation in
            observers.append(continuation)
        }
    }

    func open() {
        isOpen = true

        let pending = blocked
        blocked.removeAll()

        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor TransferJournalFake: TransferJournal {
    private var entries: [UUID: JournaledTransfer] = [:]
    private var entryAppearingDuringRecord: JournaledTransfer?
    private let recordGate: AsyncGate?
    private let readFailure: TransferJournalError?
    private var recordFailure: TransferJournalError?

    private(set) var recordCalls = 0

    init(
        existingEntry: JournaledTransfer? = nil,
        entryAppearingDuringRecord: JournaledTransfer? = nil,
        recordGate: AsyncGate? = nil,
        readFailure: TransferJournalError? = nil,
        recordFailure: TransferJournalError? = nil
    ) {
        if let existingEntry {
            entries[existingEntry.intent.id] = existingEntry
        }

        self.entryAppearingDuringRecord = entryAppearingDuringRecord
        self.recordGate = recordGate
        self.readFailure = readFailure
        self.recordFailure = recordFailure
    }

    func entry(for intentID: UUID) async throws -> JournaledTransfer? {
        if let readFailure {
            throw readFailure
        }

        return entries[intentID]
    }

    func record(
        _ intent: TransferIntent,
        idempotencyKey: UUID
    ) async throws -> JournaledTransfer {
        recordCalls += 1

        if let recordGate {
            await recordGate.wait()
        }

        if let recordFailure {
            throw recordFailure
        }

        if let entryAppearingDuringRecord {
            entries[entryAppearingDuringRecord.intent.id] =
                entryAppearingDuringRecord
            self.entryAppearingDuringRecord = nil
        }

        if let existing = entries[intent.id] {
            guard existing.intent == intent else {
                throw TransferJournalError.intentConflict
            }

            return existing
        }

        guard !entries.values.contains(where: {
            $0.idempotencyKey == idempotencyKey
        }) else {
            throw TransferJournalError.idempotencyKeyConflict
        }

        let entry = JournaledTransfer(
            intent: intent,
            idempotencyKey: idempotencyKey
        )
        entries[intent.id] = entry
        return entry
    }

    func setRecordFailure(_ failure: TransferJournalError?) {
        recordFailure = failure
    }
}

private enum GatewayFailure: Error, Sendable {
    case responseLost
}

private actor TransferGatewaySpy: TransferGateway {
    struct Observation: Equatable, Sendable {
        let received: JournaledTransfer
        let persistedAtSubmission: JournaledTransfer?
    }

    private let journal: any TransferJournal
    private let result: Result<TransferSubmissionResult, GatewayFailure>
    private let submissionGate: AsyncGate?

    private(set) var observations: [Observation] = []

    init(
        journal: any TransferJournal,
        result: Result<TransferSubmissionResult, GatewayFailure> =
            .success(.accepted),
        submissionGate: AsyncGate? = nil
    ) {
        self.journal = journal
        self.result = result
        self.submissionGate = submissionGate
    }

    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        let persisted = try await journal.entry(for: transfer.intent.id)
        observations.append(
            Observation(
                received: transfer,
                persistedAtSubmission: persisted
            )
        )

        if let submissionGate {
            await submissionGate.wait()
        }

        return try result.get()
    }
}
