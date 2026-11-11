//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import TransferCore
import TransferDomain
import TransferPersistence
import TransferSecurity
import TransferSimulation

/// Example-only composition. This is not a production banking client.
@MainActor
public final class DemoDependencies {
    public enum Failure: Error, Equatable, Sendable {
        case operationInProgress
        case invalidStep
    }

    public private(set) var approval: ApprovalRequest?
    public private(set) var state: TransferState?
    public private(set) var failure: TransferFailure?
    public private(set) var recoveredTransfers: [RecoveryCandidate] = []

    private let storeURL: URL
    private let credentials: any CredentialStore
    private let diagnostics: any TransferDiagnostics
    private let now: @Sendable () -> Date
    private let policy: ReconciliationPolicy

    private let maker: BusinessContext
    private let checker: BusinessContext
    private let bankStore: SimulatedTransferStore
    private let approvalServer: SimulatedApprovalService
    private let statusGateway: SimulatedBank

    private var journal: CoreDataTransferJournal
    private var recovery: TransferRecoveryService
    private var coordinator: TransferCoordinator?
    private var isOperating = false

    public init(
        storeURL: URL,
        credentials: any CredentialStore,
        diagnostics: any TransferDiagnostics = NoOpTransferDiagnostics(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        let organizationID = UUID()
        let maker = BusinessContext(
            organizationID: organizationID,
            userID: UUID(),
            roles: [.maker]
        )
        let checker = BusinessContext(
            organizationID: organizationID,
            userID: UUID(),
            roles: [.checker]
        )
        let bankStore = SimulatedTransferStore()
        let statusGateway = SimulatedBank(store: bankStore)
        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let policy = try ReconciliationPolicy(
            maximumAttempts: 1,
            retryDelayNanoseconds: 0
        )

        self.storeURL = storeURL
        self.credentials = credentials
        self.diagnostics = diagnostics
        self.now = now
        self.policy = policy
        self.maker = maker
        self.checker = checker
        self.bankStore = bankStore
        self.statusGateway = statusGateway
        self.journal = journal

        approvalServer = try SimulatedApprovalService(
            organizationID: organizationID,
            members: [maker, checker],
            store: bankStore
        )
        recovery = TransferRecoveryService(
            journal: journal,
            gateway: statusGateway,
            policy: policy
        )
    }

    public func requestApproval(amount: Money) async throws {
        try beginOperation()
        defer { isOperating = false }

        guard approval == nil, state == nil else {
            throw Failure.invalidStep
        }

        // Explicit simulated sign-in. This is not a bank-issued token.
        let credential = try SessionCredential(
            identity: SessionIdentity(
                organizationID: maker.organizationID,
                userID: maker.userID
            ),
            accessToken: "demo-session-not-a-bank-token",
            expiresAt: now().addingTimeInterval(900)
        )
        try await credentials.save(credential)

        let gateway = try await approvalServer.gateway(for: maker.userID)
        let service = TransferApprovalService(gateway: gateway)
        let intent = TransferIntent(id: UUID(), amount: amount)

        approval = try await service.requestApproval(for: intent)
        failure = nil
    }

    public func decide(_ decision: ApprovalDecision) async throws {
        try beginOperation()
        defer { isOperating = false }

        guard let approval, approval.state == .pending else {
            throw Failure.invalidStep
        }

        let gateway = try await approvalServer.gateway(for: checker.userID)
        let service = TransferApprovalService(gateway: gateway)

        self.approval = try await service.decide(
            approval,
            decision: decision
        )
    }

    public func submit(
        loseResponse: Bool = false,
        useBiometrics: Bool = false
    ) async throws {
        try beginOperation()
        defer { isOperating = false }

        guard let approval,
              approval.state == .approved,
              state == nil else {
            throw Failure.invalidStep
        }

        let approvalGateway = try await approvalServer.gateway(
            for: maker.userID
        )
        let service = TransferApprovalService(gateway: approvalGateway)
        let approvedGateway = try service.submissionGateway(for: approval)
        let responseGateway = DemoResponseLossGateway(
            underlying: approvedGateway,
            loseNextResponse: loseResponse
        )

        let authenticator: any StepUpAuthenticator

        if useBiometrics {
            authenticator = LocalBiometricAuthenticator()
        } else {
            authenticator = DemoStepUpAuthenticator()
        }

        let securedGateway = StepUpTransferGateway(
            sessions: SessionProvider(
                store: credentials,
                now: { [now] in now() }
            ),
            expectedIdentity: SessionIdentity(
                organizationID: maker.organizationID,
                userID: maker.userID
            ),
            authenticator: authenticator,
            underlying: responseGateway
        )
        let coordinator = TransferCoordinator(
            journal: journal,
            gateway: securedGateway,
            diagnostics: diagnostics
        )

        self.coordinator = coordinator
        state = .submitting

        do {
            state = try await coordinator.submit(approval.intent)
            failure = await coordinator.failure(for: approval.intent.id)
        } catch {
            // A later attempt still checks the durable journal first.
            self.coordinator = nil
            state = nil
            throw error
        }
    }

    public func recover() async throws {
        try beginOperation()
        defer { isOperating = false }

        try await refreshRecovery()
    }

    /// Recreates client persistence/recovery while retaining the simulated bank.
    public func recreateClientAndRecover() async throws {
        try beginOperation()
        defer { isOperating = false }

        let reopenedJournal = try CoreDataTransferJournal(storeURL: storeURL)
        let recreatedRecovery = TransferRecoveryService(
            journal: reopenedJournal,
            gateway: statusGateway,
            policy: policy
        )

        journal = reopenedJournal
        recovery = recreatedRecovery
        coordinator = nil
        state = nil
        failure = nil

        try await refreshRecovery()
    }

    /// Test/demo control. UI state changes only after status recovery.
    public func simulateSettlement() async throws {
        try beginOperation()
        defer { isOperating = false }

        guard state == .accepted,
              let approval,
              let entry = try await journal.entry(
                  for: approval.intent.id
              ) else {
            throw Failure.invalidStep
        }

        _ = try await bankStore.advanceStatus(
            for: entry.idempotencyKey,
            to: .settled
        )
        try await refreshRecovery()
    }

    public func startNewDraft() throws {
        try beginOperation()
        defer { isOperating = false }

        guard approval?.state == .rejected ||
                state == .settled ||
                state == .rejected else {
            throw Failure.invalidStep
        }

        approval = nil
        state = nil
        failure = nil
        coordinator = nil
    }

    private func beginOperation() throws {
        guard !isOperating else {
            throw Failure.operationInProgress
        }

        isOperating = true
    }

    private func refreshRecovery() async throws {
        recoveredTransfers = try await recovery.recover()

        guard let intentID = approval?.intent.id,
              let candidate = recoveredTransfers.first(
                  where: { $0.id == intentID }
              ) else {
            return
        }

        switch candidate.reconciliation {
        case .confirmed(let confirmedState, _):
            state = confirmedState
            failure = nil

        case .unresolved:
            // An unresolved query must not erase previously known state.
            if state == nil {
                state = .unknown
            }
            if failure == nil {
                failure = .unknownOutcome
            }
        }
    }
}

@MainActor
private final class DemoStepUpAuthenticator: StepUpAuthenticator {
    func authenticate(reason: String) async throws {
        try Task.checkCancellation()
    }
}

/// Drops an accepted response after the approval-protected gateway completes.
private actor DemoResponseLossGateway: TransferGateway {
    private let underlying: any TransferGateway
    private var loseNextResponse: Bool

    init(
        underlying: any TransferGateway,
        loseNextResponse: Bool
    ) {
        self.underlying = underlying
        self.loseNextResponse = loseNextResponse
    }

    func submit(
        _ transfer: JournaledTransfer
    ) async throws -> TransferSubmissionResult {
        let shouldLoseResponse = loseNextResponse
        loseNextResponse = false

        let result = try await underlying.submit(transfer)

        if shouldLoseResponse, result == .accepted {
            throw TransferFailure.transportFailure
        }

        return result
    }
}
