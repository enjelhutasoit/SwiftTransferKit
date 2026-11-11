//
// Copyright (c) 2026 Enjel Hutasoit
//

import SwiftUI
import TransferCore

@MainActor
struct TransferView: View {
    @ObservedObject var model: TransferViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Simulation only. No real money or banking connection.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("1. Maker") {
                    TextField("Amount in whole rupiah", text: $model.amountText)
                        .keyboardType(.numberPad)
                        .disabled(!model.canRequest)

                    Button("Request approval as maker") {
                        Task { await model.requestApproval() }
                    }
                    .disabled(!model.canRequest)
                }

                Section("2. Checker") {
                    Text(model.approvalText)

                    HStack {
                        Button("Approve") {
                            Task { await model.decide(.approve) }
                        }

                        Spacer()

                        Button("Reject", role: .destructive) {
                            Task { await model.decide(.reject) }
                        }
                    }
                    .disabled(!model.canDecide)
                }

                Section {
                    Toggle("Lose submission response", isOn: $model.loseResponse)
                    Toggle("Use device biometrics", isOn: $model.useBiometrics)

                    Button("Submit approved transfer") {
                        Task { await model.submit() }
                    }
                    .disabled(!model.canSubmit)
                } header: {
                    Text("3. Submission")
                } footer: {
                    Text(
                        "Response loss happens after simulated acceptance. When device biometrics are off, step-up is simulated."
                    )
                }

                Section("Current transfer") {
                    TransferStatusView(state: model.transferState)

                    if let message = model.message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if model.isBusy {
                        ProgressView("Working")
                    }
                }

                Section("4. Recovery") {
                    Button("Check status") {
                        Task { await model.recover() }
                    }

                    Button("Recreate client and recover") {
                        Task { await model.recreateClientAndRecover() }
                    }

                    Text(
                        "Client recreation keeps the simulated bank running. Closing the entire app resets that bank; retained transfers may then remain unresolved."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Simulated bank") {
                    Button("Simulate settlement and check status") {
                        Task { await model.simulateSettlement() }
                    }
                    .disabled(!model.canSettle)

                    Button("Start a new transfer") {
                        Task { await model.startNewDraft() }
                    }
                    .disabled(!model.canStartNewDraft)
                }

                if !model.recoveredTransfers.isEmpty {
                    Section("Retained transfers") {
                        ForEach(model.recoveredTransfers) { candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Intent \(candidate.id.uuidString.prefix(8))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                switch candidate.reconciliation {
                                case .confirmed(let state, _):
                                    TransferStatusView(state: state)

                                case .unresolved:
                                    Text("No new confirmation")
                                        .font(.headline)
                                    Text("This does not establish rejection.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .disabled(model.isBusy)
            .navigationTitle("Business Transfer")
            .task {
                await model.load()
            }
        }
    }
}
