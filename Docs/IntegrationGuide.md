# Integration Guide

## Requirements

- Xcode 16.2.
- Swift 6.0.3 in Swift 6 language mode.
- iOS 17 or later.
- macOS 12 or later is declared for package host builds and tests.
- No third-party Swift package dependencies.

Release availability is established by repository tags and release records,
not by the presence of this guide.

## Add the Local Package

1. Clone the repository into a folder named SwiftTransferKit.
2. In Xcode, open the consuming application.
3. Choose File > Add Package Dependencies.
4. Choose Add Local and select the repository root containing Package.swift.
5. Add only the products required by the application target.

For the simulation example below, add:

- TransferDomain
- TransferCore
- TransferPersistence
- TransferSimulation

TransferSimulation is for tests and demonstrations only.
TransferDemoSupport contains example composition and is not a production
integration dependency.

After a release exists, consumers may select its published version through
Xcode's package dependency interface.

## Minimal Simulated Client

The following source demonstrates journal-before-send and status lookup.
It does not implement the maker-checker or authentication flow.

```swift
import Foundation
import TransferCore
import TransferDomain
import TransferPersistence
import TransferSimulation

struct SimulatedTransferClient: Sendable {
    private let coordinator: TransferCoordinator
    private let reconciler: TransferReconciliationService

    init(storeURL: URL) throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let journal = try CoreDataTransferJournal(storeURL: storeURL)
        let bank = SimulatedBank()

        coordinator = TransferCoordinator(
            journal: journal,
            gateway: bank
        )

        reconciler = TransferReconciliationService(
            journal: journal,
            gateway: bank,
            policy: try ReconciliationPolicy(
                maximumAttempts: 3,
                retryDelayNanoseconds: 1_000_000_000
            )
        )
    }

    func submit(
        intentID: UUID,
        minorUnits: Int64
    ) async throws -> TransferState {
        let amount = try Money(
            minorUnits: minorUnits,
            currencyCode: "IDR",
            scale: 2
        )

        let intent = TransferIntent(
            id: intentID,
            amount: amount
        )

        return try await coordinator.submit(intent)
    }

    func reconcile(
        intentID: UUID
    ) async throws -> ReconciliationResult {
        try await reconciler.reconcile(intentID: intentID)
    }
}
```

Retain the client for the workflow. Use a writable Application Support
location for storeURL.

Create the intent UUID once per business action and reuse it when referring
to that same action. Do not generate a new UUID in response to a timeout.

For IDR with scale 2, 10,000 minor units represent IDR 100.
Do not construct financial amounts through floating-point arithmetic.

Creating a new client also creates a new in-memory simulated bank.
It cannot recover server records from a previous client instance.

## Interpreting Results

- accepted means acknowledged, not settled.
- rejected requires an authoritative response.
- unknown requires reconciliation.
- An unresolved lookup does not prove rejection.
- Preparation failures are thrown before gateway submission.
- Gateway failures preserve unknown; operational classification is available
  from TransferCoordinator.failure(for:).

A reconciliation result does not mutate TransferCoordinator's cached state.
Present the authoritative reconciliation result separately.

## Complete Demo Composition

Open:

Examples/BusinessTransferDemo/BusinessTransferDemo.xcodeproj

Select the BusinessTransferDemo scheme and an iOS Simulator.

The composition in Infrastructure/DemoDependencies.swift demonstrates:

- Maker and checker approval.
- A durable Core Data journal.
- Synthetic session credentials.
- Simulated or device biometric step-up.
- Response loss after simulated acceptance.
- Client recreation and status reconciliation.
- Simulated settlement.

Use the simulator mode for deterministic demonstrations.
Device biometrics require the host's Face ID usage description.

## Backend Adapter Responsibilities

A real integration must provide authenticated submission and status adapters.
The current HTTP adapter does not supply a complete authenticated backend
integration.

The backend must enforce durable idempotency, permissions, approval,
transaction limits, payload consistency, and authoritative financial state.

Status adapters must preserve intent/key identity and the server's version
contract. Client timestamps are not a substitute for server ordering.

## Verification

Run from the repository root:

```bash
xcrun swift test
xcodebuild -list
xcrun simctl list devices available
```

Set TRANSFER_SIMULATOR_ID to the UUID of an available simulator, then run:

```bash
xcodebuild \
  -scheme SwiftTransferKit \
  -destination "platform=iOS Simulator,id=$TRANSFER_SIMULATOR_ID" \
  -parallel-testing-enabled NO \
  test
```

Build the demo:

```bash
xcodebuild \
  -project Examples/BusinessTransferDemo/BusinessTransferDemo.xcodeproj \
  -scheme BusinessTransferDemo \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Record actual results, runtime versions, and the tested commit SHA.
A command listed in documentation is not evidence that it passed.
