//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import SwiftUI
import TransferDemoSupport
import TransferObservability
import TransferSecurity

@main
@MainActor
struct BusinessTransferDemoApp: App {
    @StateObject private var model = DemoAppModel()

    var body: some Scene {
        WindowGroup {
            if let transferModel = model.transferModel {
                TransferView(model: transferModel)
            } else {
                VStack(spacing: 12) {
                    Text("Demo unavailable")
                        .font(.headline)

                    Text(model.setupMessage ?? "The demo could not be initialized.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}

@MainActor
private final class DemoAppModel: ObservableObject {
    @Published private(set) var transferModel: TransferViewModel?
    @Published private(set) var setupMessage: String?

    init() {
        do {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = applicationSupport.appendingPathComponent(
                "SwiftTransferKitDemo",
                isDirectory: true
            )

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let credentials = try KeychainCredentialStore(
                service: "com.enjelhutasoit.BusinessTransferDemo.session"
            )
            let dependencies = try DemoDependencies(
                storeURL: directory.appendingPathComponent("journal.sqlite"),
                credentials: credentials,
                diagnostics: OSLogTransferDiagnostics()
            )

            transferModel = TransferViewModel(dependencies: dependencies)
        } catch {
            setupMessage = "Local storage could not be prepared. No transfer was submitted."
        }
    }
}
