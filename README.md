# SwiftTransferKit

A simulated B2B financial-transfer reliability SDK for Swift.

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

For iOS Simulator testing, use the SwiftTransferKit scheme and a concrete
simulator UUID as described in the integration guide.

## Run the Demo

Keep the repository folder named SwiftTransferKit.

Open:

Examples/BusinessTransferDemo/BusinessTransferDemo.xcodeproj

Select BusinessTransferDemo, choose an iOS Simulator, and run.

The demo shows approval, lost responses, recovery, and simulated settlement.
Its backend exists only in memory. Restarting the whole application discards
that backend state.

## CI and Release Evidence

The Swift verification workflow checks:

1. Xcode 16.2, Swift 6.0.3, and Intel architecture.
2. All macOS package tests.
3. All package tests on iOS 18.2 Simulator.
4. A Release simulator build of the demo.

The workflow runs only for public repositories to avoid private-repository
compute charges. A skipped workflow is not verification.

Inspect [Actions](https://github.com/enjelhutasoit/SwiftTransferKit/actions)
for the exact source SHA and execution results.

CI logs and the job summary are retained by GitHub according to repository
settings. This workflow does not upload build artifacts or publish releases.

An iOS 17 runtime check and manual demo checks remain separate release gates.

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
