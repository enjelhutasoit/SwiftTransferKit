//
// Copyright (c) 2026 Enjel Hutasoit
//

import SwiftUI
import TransferCore
import TransferDomain

enum DemoTheme {
    static let gold = Color(red: 0.71, green: 0.60, blue: 0.34)
    static let accent = Color(red: 0.48, green: 0.36, blue: 0.14)
    static let black = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let success = Color(red: 0.09, green: 0.39, blue: 0.26)
    static let destructive = Color(red: 0.70, green: 0.15, blue: 0.12)
}

struct TransferActionStyle: ButtonStyle {
    let color: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(
                color,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

@MainActor
struct TransferView: View {
    @ObservedObject var model: TransferViewModel

    @State private var selectedTab: Tab = .transfers
    @State private var showsRejectionConfirmation = false
    @State private var showsRecreationConfirmation = false
    @FocusState private var amountIsFocused: Bool

    private enum Tab: Hashable {
        case transfers
        case approvals
        case simulation
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                transferForm
                    .navigationTitle("Transfers")
            }
            .tabItem {
                Label("Transfers", systemImage: "arrow.left.arrow.right")
            }
            .tag(Tab.transfers)

            NavigationStack {
                approvalForm
                    .navigationTitle("Approvals")
            }
            .tabItem {
                Label("Approvals", systemImage: "checkmark.seal")
            }
            .tag(Tab.approvals)

            NavigationStack {
                simulationForm
                    .navigationTitle("Simulation Lab")
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
            .environment(\.colorScheme, .dark)
            .tint(DemoTheme.gold)
            .tabItem {
                Label("Simulation Lab", systemImage: "slider.horizontal.3")
            }
            .tag(Tab.simulation)
        }
        .tint(DemoTheme.accent)
        .task {
            await model.load()
        }
        .alert(
            "Reject this request?",
            isPresented: $showsRejectionConfirmation
        ) {
            Button("Keep request", role: .cancel) {}

            Button("Reject request", role: .destructive) {
                Task {
                    await model.decide(.reject)
                    selectedTab = .transfers
                }
            }
        } message: {
            Text(
                "This rejects the approval request. No transfer will be submitted."
            )
        }
    }

    private var transferForm: some View {
        Form {
            Section {
                HStack(spacing: 12) {
//                    Image(systemName: "arrow.left.arrow.right")
//                        .font(.title2)
//                        .foregroundStyle(DemoTheme.gold)
//                        .accessibilityHidden(true)
                    
                    Image("NavigationLogo")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)


                    VStack(alignment: .leading, spacing: 4) {
                        Text("SwiftTransferKit")
                            .font(.headline)

                        Text("Business transfer demo")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Simulation only. No real money.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if model.canRequest {
                Section {
                    TextField(
                        "Amount in whole rupiah",
                        text: $model.amountText
                    )
                    .keyboardType(.numberPad)
                    .font(.title2.monospacedDigit())
                    .focused($amountIsFocused)
                    .accessibilityLabel("Transfer amount in whole rupiah")

                    Button {
                        amountIsFocused = false

                        Task {
                            await model.requestApproval()

                            if model.canDecide {
                                selectedTab = .approvals
                            }
                        }
                    } label: {
                        Label(
                            "Request approval",
                            systemImage: "arrow.right"
                        )
                    }
                    .buttonStyle(
                        TransferActionStyle(color: DemoTheme.black)
                    )
                } header: {
                    Text("1. Transfer amount · Maker")
                } footer: {
                    Text(
                        "Enter a positive whole-rupiah amount. A checker must approve before you can send."
                    )
                }
            } else {
                Section("Transfer details") {
                    LabeledContent("Amount", value: "IDR \(model.amountText)")
                    LabeledContent("Approval", value: model.approvalText)
                }
            }

            Section("Next step") {
                Text(nextStep)
                    .font(.subheadline)

                if model.canDecide {
                    Button {
                        selectedTab = .approvals
                    } label: {
                        Label(
                            "Review approval",
                            systemImage: "checkmark.seal"
                        )
                    }
                    .buttonStyle(
                        TransferActionStyle(color: DemoTheme.black)
                    )
                }

                if model.canSubmit {
                    Button {
                        Task { await model.submit() }
                    } label: {
                        Label(
                            "Send transfer",
                            systemImage: "paperplane.fill"
                        )
                    }
                    .buttonStyle(
                        TransferActionStyle(color: DemoTheme.success)
                    )
                }

                if model.transferState == .unknown ||
                    model.transferState == .accepted {
                    Button {
                        Task { await model.recover() }
                    } label: {
                        Label(
                            "Check transfer status",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(
                        TransferActionStyle(color: DemoTheme.black)
                    )
                }

                if model.canStartNewDraft {
                    Button {
                        Task { await model.startNewDraft() }
                    } label: {
                        Label(
                            "Start a new transfer",
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(
                        TransferActionStyle(color: DemoTheme.black)
                    )
                }
            }

            Section("Transfer status") {
                TransferStatusView(state: model.transferState)
            }

            Section {
                LabeledContent(
                    "Response",
                    value: model.loseResponse ? "Simulated loss" : "Normal"
                )

                LabeledContent(
                    "Authentication",
                    value: model.useBiometrics ? "Device biometrics" : "Simulated"
                )

                Button("Open Simulation Lab") {
                    selectedTab = .simulation
                }
            } header: {
                Text("Demo configuration")
            } footer: {
                Text(
                    "Test controls and simulated bank actions are kept in Simulation Lab."
                )
            }

            feedback

            Section("Retained transfers") {
                Button {
                    Task { await model.recover() }
                } label: {
                    Label(
                        "Refresh retained transfers",
                        systemImage: "arrow.clockwise"
                    )
                }

                if model.recoveredTransfers.isEmpty {
                    Text("No retained transfers found.")
                        .foregroundStyle(.secondary)
                }

                ForEach(model.recoveredTransfers) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reference \(candidate.id.uuidString.prefix(8))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        switch candidate.reconciliation {
                        case .confirmed(let state, _):
                            TransferStatusView(state: state)

                        case .unresolved:
                            Label(
                                "No new confirmation",
                                systemImage: "questionmark.circle"
                            )
                            .font(.headline)

                            Text(
                                "The outcome remains unresolved. This is not confirmation of rejection."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.isBusy)
    }

    private var approvalForm: some View {
        Form {
            Section {
                Label("Checker workspace", systemImage: "person.badge.shield.checkmark")
                    .font(.headline)

                Text(
                    "You are acting as a separate simulated checker. Review the maker's request before deciding."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("Approval request") {
                Text(model.approvalText)
                    .font(.headline)

                if model.approvalState != nil {
                    LabeledContent(
                        "Requested amount",
                        value: "IDR \(model.amountText)"
                    )
                }

                if model.canDecide {
                    Button {
                        Task {
                            await model.decide(.approve)

                            if model.canSubmit {
                                selectedTab = .transfers
                            }
                        }
                    } label: {
                        Label(
                            "Approve transfer",
                            systemImage: "checkmark"
                        )
                    }
                    .buttonStyle(
                        TransferActionStyle(color: DemoTheme.success)
                    )

                    Button(role: .destructive) {
                        showsRejectionConfirmation = true
                    } label: {
                        Label(
                            "Reject request",
                            systemImage: "xmark"
                        )
                    }
                    .buttonStyle(
                        TransferActionStyle(color: DemoTheme.destructive)
                    )
                } else {
                    Text(
                        "Only a pending request can be approved or rejected."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Button("Back to Transfers") {
                    selectedTab = .transfers
                }
            }

            feedback
        }
        .disabled(model.isBusy)
    }

    private var simulationForm: some View {
        Form {
            Section {
                Label("Test controls only", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
                    .foregroundStyle(DemoTheme.gold)

                Text(
                    "These controls configure the demo or manipulate its in-memory bank. They are not customer banking actions."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Lose submission response",
                    isOn: $model.loseResponse
                )

                Toggle(
                    "Use device biometrics",
                    isOn: $model.useBiometrics
                )
            } header: {
                Text("Before sending")
            } footer: {
                Text(
                    "Response loss happens after bank acceptance. With biometrics off, authentication is simulated. Configure these options before submission."
                )
            }
            .disabled(model.transferState != nil)

            Section {
                Button {
                    Task { await model.simulateSettlement() }
                } label: {
                    Label(
                        "Simulate settlement and refresh",
                        systemImage: "building.columns"
                    )
                }
                .disabled(!model.canSettle)

                Text(
                    "Available after acceptance is confirmed. If the outcome is unknown, first check status in Transfers."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("Simulated bank")
            }

            Section {
                Button {
                    showsRecreationConfirmation = true
                } label: {
                    Label(
                        "Recreate client and recover",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }

                Text(
                    "Reopens client storage and recovers retained transfers while keeping the simulated bank running."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text(
                    "Closing the entire app also resets the in-memory bank. Old journal entries may then remain unresolved."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("Client recovery")
            }

            feedback

            Section {
                Button("Return to Transfers") {
                    selectedTab = .transfers
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DemoTheme.black)
        .disabled(model.isBusy)
        .confirmationDialog(
            "Recreate the demo client?",
            isPresented: $showsRecreationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Recreate client") {
                Task {
                    await model.recreateClientAndRecover()
                    selectedTab = .transfers
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The journal and simulated bank are kept. Current client state is rebuilt from recovery results."
            )
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if model.isBusy || model.message != nil {
            Section("Activity") {
                if model.isBusy {
                    ProgressView("Processing")
                }

                if let message = model.message {
                    Label(message, systemImage: "info.circle")
                        .font(.subheadline)
                }
            }
        }
    }

    private var nextStep: String {
        if model.canDecide {
            return "2. A checker must review this request in Approvals."
        }

        if model.canSubmit {
            return "3. Approval is complete. Send the transfer as the maker."
        }

        if model.transferState == .unknown {
            return "The result is unknown. Check status before taking another action."
        }

        if model.transferState == .accepted {
            return "The bank accepted the transfer. Settlement is still pending."
        }

        if model.canStartNewDraft {
            return "This workflow is complete. You can start a separate transfer."
        }

        return "1. Enter the amount and request approval."
    }
}
