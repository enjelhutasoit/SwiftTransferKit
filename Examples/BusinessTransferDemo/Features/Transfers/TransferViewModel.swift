//
// Copyright (c) 2026 Enjel Hutasoit
//

import Combine
import Foundation
import TransferCore
import TransferDemoSupport
import TransferDomain

@MainActor
final class TransferViewModel: ObservableObject {
    @Published var amountText = "100000"
    @Published var loseResponse = false
    @Published var useBiometrics = false

    @Published private(set) var approvalState: ApprovalState?
    @Published private(set) var transferState: TransferState?
    @Published private(set) var recoveredTransfers: [RecoveryCandidate] = []
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?

    private let dependencies: DemoDependencies
    private var didLoad = false

    init(dependencies: DemoDependencies) {
        self.dependencies = dependencies
    }

    var canRequest: Bool {
        approvalState == nil && transferState == nil
    }

    var canDecide: Bool {
        approvalState == .pending
    }

    var canSubmit: Bool {
        approvalState == .approved && transferState == nil
    }

    var canSettle: Bool {
        transferState == .accepted
    }

    var canStartNewDraft: Bool {
        approvalState == .rejected ||
            transferState == .settled ||
            transferState == .rejected
    }

    var approvalText: String {
        switch approvalState {
        case .none:
            return "No request"
        case .some(.pending):
            return "Waiting for checker"
        case .some(.approved):
            return "Approved by checker"
        case .some(.rejected):
            return "Rejected by checker"
        }
    }

    func load() async {
        guard !didLoad else {
            return
        }
        didLoad = true
        await recover()
    }

    func requestApproval() async {
        await perform {
            let amount = try makeAmount()
            try await dependencies.requestApproval(amount: amount)
        }
    }

    func decide(_ decision: ApprovalDecision) async {
        await perform {
            try await dependencies.decide(decision)
        }
    }

    func submit() async {
        await perform {
            try await dependencies.submit(
                loseResponse: loseResponse,
                useBiometrics: useBiometrics
            )
        }
    }

    func recover() async {
        await perform {
            try await dependencies.recover()
        }
    }

    func recreateClientAndRecover() async {
        await perform {
            try await dependencies.recreateClientAndRecover()
        }
    }

    func simulateSettlement() async {
        await perform {
            try await dependencies.simulateSettlement()
        }
    }

    func startNewDraft() async {
        await perform {
            try dependencies.startNewDraft()
        }
    }

    private func perform(
        _ operation: @MainActor () async throws -> Void
    ) async {
        guard !isBusy else {
            return
        }

        isBusy = true
        message = nil

        defer {
            refresh()
            isBusy = false
        }

        do {
            try await operation()
        } catch is InputFailure {
            message = "Enter a positive whole-rupiah amount within the supported range."
        } catch is CancellationError {
            message = "The operation was cancelled. Check status before continuing."
        } catch {
            message = "The operation could not complete. Review the current status before continuing."
        }
    }

    private func refresh() {
        approvalState = dependencies.approval?.state
        transferState = dependencies.state
        recoveredTransfers = dependencies.recoveredTransfers

        guard message == nil, let failure = dependencies.failure else {
            return
        }

        switch failure.suggestedAction {
        case .correctInput:
            message = "Review the transfer input."

        case .signIn:
            message = "The session requires sign-in. Keep the existing transfer identity."

        case .authenticate:
            message = "Local authentication did not complete. Keep the transfer for reconciliation."

        case .checkAuthenticationAvailability:
            message = "Check device authentication availability. The transfer remains retained."

        case .reviewAccess:
            message = "The session does not have the required access."

        case .reviewConfiguration:
            message = "The application configuration needs review."

        case .reconcile:
            message = "The outcome is unresolved. Check status; do not submit again."
        }
    }

    private func makeAmount() throws -> Money {
        let input = amountText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rupiah = Int64(input), rupiah > 0 else {
            throw InputFailure.invalidAmount
        }

        let conversion = rupiah.multipliedReportingOverflow(by: 100)

        guard !conversion.overflow else {
            throw InputFailure.invalidAmount
        }

        return try Money(
            minorUnits: conversion.partialValue,
            currencyCode: "IDR",
            scale: 2
        )
    }

    private enum InputFailure: Error {
        case invalidAmount
    }
}
