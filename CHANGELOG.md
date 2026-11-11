# Changelog

This file records release scope.

A version section does not prove publication or successful verification.
The Git tag, GitHub release, and execution evidence establish release status.

## v1.0.0 Scope

### Domain and Orchestration

- Exact positive IDR amounts represented in integer minor units.
- Immutable transfer identity and explicit lifecycle transitions.
- Journal-before-send coordination and stable idempotency keys.
- Unknown outcomes for ambiguous submission failures.
- Bounded authoritative status reconciliation.
- Server-version ordering and conflict detection.
- Recovery from durable journal entries.
- Separate approval and financial states.
- Advisory local transfer policy evaluation.
- Typed operational failure classification.

### Adapters

- Core Data transfer journal.
- URLSession submission adapter for the simulated HTTP contract.
- Keychain credential storage and local session validation.
- LocalAuthentication biometric step-up.
- Allowlisted OSLog diagnostics.

### Simulation and Demo

- In-memory simulated backend with uniqueness checks.
- Controlled response loss and delayed responses.
- Simulated maker-checker authorization.
- Thin SwiftUI business transfer demo.
- Client recreation and simulated settlement controls.

### Verification and Documentation

- Deterministic behavioral unit and integration tests.
- Failure scenario coverage matrix.
- Xcode 16.2 CI for macOS tests, iOS Simulator tests, and demo build.
- Architecture, integration, threat model, and limitation documents.

### Known Limitations

- No real-money movement, payment rails, ledger, or production bank integration.
- No authenticated HTTP submission or production HTTP status adapter.
- Simulated backend state is not durable.
- Financial status and ordering snapshots are process-local.
- No production journal migration, retention, or capacity guarantee.
- Local security checks do not replace backend authorization.
- Simulator verification does not establish physical biometric correctness.
- No App Store deployment or automatic release publication.

### Publication Gate

Publish v1.0.0 only after:

- The final main-branch SHA passes all CI verification steps.
- Package tests pass on an iOS 17 runtime.
- Manual demo flows pass with recorded outcomes.
- Known limitations match the implementation.
- The release record includes the tested SHA, toolchain, runtime versions,
  and CI run URL.

Earlier milestone release dates and verification results are not reconstructed
without their original evidence.
