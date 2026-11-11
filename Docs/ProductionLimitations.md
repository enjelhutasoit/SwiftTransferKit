# Production Limitations

SwiftTransferKit is a simulated educational and portfolio SDK.
It does not move money or integrate with a bank.

## Backend and Financial Authority

- The simulated bank stores its state in memory.
- Process termination discards simulated bank and approval state.
- There is no ledger, balance management, payment rail, or settlement engine.
- Real backend idempotency, authorization, approval, and durability are required.
- Local limits are advisory and do not enforce financial authority.

## Networking

- HTTPTransferGateway implements a simulated submission contract.
- It does not attach authorization tokens or implement token refresh.
- There is no production HTTP status lookup adapter.
- HTTPS validation is not a complete transport-security assessment.
- No production backend availability or performance target has been measured.

## Persistence and Recovery

- The journal stores intent payloads and stable idempotency keys.
- It does not persist the latest financial state or status version.
- Reconciliation ordering knowledge is process-local.
- Recovery scans existing entries without automatic pruning.
- There is no retention policy or production migration guarantee.
- An unknown or not-found outcome does not authorize a new transfer identity.
- No automatic resubmission or guaranteed background recovery is provided.
- Journal capacity and long-running workload performance are unmeasured.

## Security

- Local sessions and biometrics are client-side checks.
- Server authentication, revocation, permissions, and limits remain required.
- The demo credential is synthetic and is not a banking credential.
- Keychain and LocalAuthentication adapters require platform verification.
- Automated tests do not exercise real biometrics.
- No application-level journal encryption or secure erasure is implemented.

## Demo Behavior

The demo uses an in-process simulated bank, not HTTPTransferGateway.

"Recreate client and recover" recreates client components while retaining
the simulated bank in the same process.

A complete application restart creates a new simulated bank.
Previously journaled transfers may therefore remain unresolved because
their simulated server records no longer exist.

The demo project currently expects the repository folder to be named
SwiftTransferKit. The CI checkout uses that name.

The demo separates Transfers, Approvals, and Simulation Lab.

Transfers and Approvals present the simulated customer and checker workflows.
Simulation Lab uses a separate dark appearance for fault configuration,
simulated settlement, and client recreation.

Response loss is disabled by default.
Green identifies approval and submission actions; red identifies rejection.
Labels and confirmation dialogs communicate meaning independently of color.

The role switch is a demo convenience, not a production authorization boundary.

## Verification Boundaries

- macOS tests do not replace iOS Simulator tests.
- Simulator tests do not prove physical-device biometric behavior.
- Client recreation tests do not constitute OS process-kill testing.
- A Release simulator build is not an App Store archive or deployment.
- CI requires Xcode 16.2, Swift 6.0.3, and Intel architecture.
- CI selects an already-installed compatible iOS Simulator and records its version.
- CI does not download additional simulator runtimes.
- Missing toolchains or compatible simulators fail verification.
- Local verification uses the user's existing compatible simulator runtime.
- iOS 17 is the minimum deployment target; execution on iOS 17 is not claimed
  unless actual test evidence is recorded.
- Manual demo checks remain a separate release gate.
- Apple silicon execution, unexecuted iOS versions, load testing, and
  production security assessment are not claimed.
  
## Meaning of v1.0.0

The version identifies the documented simulated SDK contract.

Public SDK source-breaking changes require a major version change.
Backward-compatible additions use minor versions, and compatible fixes
use patch versions.

TransferSimulation and TransferDemoSupport are test/demo facilities and
are excluded from the production SDK integration contract.

The version does not establish payment safety, regulatory compliance,
production readiness, or professional banking employment.
