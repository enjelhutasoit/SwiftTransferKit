<p align="center">
  <img
    src="Docs/Assets/swifttransferkit-logo.png"
    alt="SwiftTransferKit transfer symbol"
    width="180"
  />
</p>

<h1 align="center">SwiftTransferKit</h1>

<p align="center">
  A simulated B2B financial-transfer reliability SDK for Swift.
</p>

<p align="center">
  <a href="https://github.com/enjelhutasoit/SwiftTransferKit/actions/workflows/swift-tests.yml">
    <img src="https://github.com/enjelhutasoit/SwiftTransferKit/actions/workflows/swift-tests.yml/badge.svg?branch=main" alt="Swift verification on main" />
  </a>
  <img src="https://img.shields.io/badge/Swift-6.0.3-B69A57?style=flat&labelColor=171717" alt="Swift 6.0.3" />
  <img src="https://img.shields.io/badge/Xcode-16.2-8B8F96?style=flat&labelColor=171717" alt="Xcode 16.2" />
  <img src="https://img.shields.io/badge/iOS-17%2B-8B8F96?style=flat&labelColor=171717" alt="iOS 17 or later deployment target" />
  <img src="https://img.shields.io/badge/SPM-compatible-B69A57?style=flat&labelColor=171717" alt="Swift Package Manager compatible" />
  <img src="https://img.shields.io/badge/Package_dependencies-0-8B8F96?style=flat&labelColor=171717" alt="Zero third-party package dependencies" />
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-B69A57?style=flat&labelColor=171717" alt="MIT License" />
  </a>
</p>

SwiftTransferKit demonstrates journal-before-send, stable intent identity,
idempotency boundaries, explicit unknown outcomes, authoritative status
reconciliation, maker-checker approval, and local security adapters.

It does not move real money or integrate with a bank.

## Requirements

- Xcode 16.2.
- Swift 6.0.3, Swift 6 language mode.
- iOS 17 or later.
- Zero third-party Swift package dependencies.

macOS 12 or later is also declared for package host builds and tests.

Use an already-installed compatible iOS Simulator runtime.
No additional runtime installation is required by these instructions.

The iOS badge states the deployment target, not verified runtime coverage.

## Start Here

- [Integration guide](Docs/IntegrationGuide.md)
- [Architecture](Docs/Architecture.md)
- [Security threat model](Docs/SecurityThreatModel.md)
- [Production limitations](Docs/ProductionLimitations.md)
- [Failure scenario matrix](Docs/FailureScenarioMatrix.md)
- [Changelog](CHANGELOG.md)

## Products

| Product | Purpose |
|---|---|
| TransferDomain | Money, intents, lifecycle, approval, and failure types |
| TransferCore | Submission, reconciliation, recovery, and orchestration contracts |
| TransferPersistence | Core Data transfer journal |
| TransferNetworking | URLSession submission adapter |
| TransferSecurity | Keychain, session checks, and local biometric step-up |
| TransferObservability | Privacy-conscious OSLog diagnostics |
| TransferSimulation | In-memory simulated backend for tests and demos |
| TransferDemoSupport | Example composition; not a production SDK dependency |

SDK targets are UI-free. The SwiftUI application lives under Examples.

## Reliability Rules

- Persist identity and the idempotency key before submission.
- Reuse the same identity for the same business action.
- A timeout does not establish financial failure.
- Acceptance does not establish settlement.
- Query authoritative status instead of blindly creating a replacement intent.
- Order status using server-defined versions when available.
- Treat local roles, limits, sessions, and biometrics as client-side checks.

A real backend remains responsible for financial authority and durable
idempotency.

## Run Tests

From the repository root:

```bash
xcrun swift test
```

This runs package tests on the Mac host.

For iOS Simulator tests, use the SwiftTransferKit scheme and the UUID of
an already-installed compatible simulator, as described in the integration guide.

## Run the Demo

Keep the repository folder named SwiftTransferKit.

Open:

```text
Examples/BusinessTransferDemo/BusinessTransferDemo.xcodeproj
```

Select BusinessTransferDemo, choose an existing iOS Simulator, and run.

### Transfers

1. Enter an amount in whole rupiah.
2. Select Request approval.
3. Open Approvals and approve the request as the simulated checker.
4. Return to Transfers and select Send transfer.
5. Read the confirmed status.

Accepted means processing, not settled.

### Approvals

Approve or reject the current request as the simulated checker.
Rejection requires confirmation.

Role switching is a demo convenience, not a production authentication system.

### Simulation Lab

This separate dark screen contains test controls:

- Lose the submission response after simulated acceptance.
- Enable device biometric authentication.
- Simulate settlement and check status.
- Recreate the client while keeping the simulated bank running.

Response loss is off by default.
With response loss enabled, check status after an unknown outcome.
Do not create a replacement transfer merely because the response was lost.

The simulated backend exists only in memory.
Restarting the entire app discards that backend state.
Previously journaled transfers may remain unresolved.

## CI and Release Evidence

The Swift verification workflow checks:

1. Xcode 16.2, Swift 6.0.3, and Intel architecture.
2. All macOS package tests.
3. All package tests on an already-installed compatible iOS Simulator.
4. A Release simulator build of the demo.

The workflow records the selected simulator runtime and source SHA.
It does not download runtimes.
If the required toolchain or a compatible simulator is unavailable,
verification fails with an environment error.

The workflow runs only for public repositories to avoid private-repository
compute charges. A skipped workflow is not verification.

Inspect [Actions](https://github.com/enjelhutasoit/SwiftTransferKit/actions)
for execution results. The README badge tracks main.

CI logs and the job summary are retained according to repository settings.
This workflow does not upload build artifacts or publish releases.

Manual demo checks remain a release gate.
Runtime versions that were not executed, including iOS 17 when unavailable,
must be recorded as unverified.

See [Releases](https://github.com/enjelhutasoit/SwiftTransferKit/releases)
for published versions. Documentation alone does not establish a release.

## Scope

This is an educational and portfolio simulation.

It does not provide payment rails, a ledger, a production authenticated
banking backend, regulatory compliance, or proof of real-money safety.

The HTTP submission adapter does not attach credentials, and no production
HTTP status lookup adapter is included.

See the production limitations before evaluating integration suitability.

## License

See [LICENSE](LICENSE).
