# Architecture

SwiftTransferKit is a simulated B2B transfer reliability SDK.
Its SDK targets contain no UI.

## Module Responsibilities

| Module | Responsibility |
|---|---|
| TransferDomain | Exact money, intent identity, lifecycle, approval types, typed failures, and status ordering |
| TransferCore | Submission, reconciliation, recovery, approval orchestration, policies, and diagnostic contracts |
| TransferPersistence | Core Data implementation of the durable transfer journal |
| TransferNetworking | URLSession submission adapter for the simulated HTTP contract |
| TransferSecurity | Credential storage, local session validation, and local step-up authentication |
| TransferObservability | OSLog implementation of the diagnostic contract |
| TransferSimulation | In-memory bank and approval simulation for tests and demonstrations |
| TransferDemoSupport | Example composition under Examples; not a production SDK component |

TransferDomain has no networking, persistence, security-framework, or UI
dependency. TransferCore depends on TransferDomain and defines ports.
Adapters depend inward on these contracts.

The SwiftUI application composes dependencies. It does not establish
financial authority.

## Submission

1. The caller creates an immutable intent with a stable UUID.
2. TransferCoordinator reserves local submission state before suspension.
3. The coordinator checks the durable journal.
4. A new intent and its idempotency key are persisted before gateway submission.
5. The gateway receives the journal's returned entry.
6. An authoritative response may establish acceptance or rejection.
7. A gateway error preserves an unknown financial outcome.

Repeated calls through one coordinator reuse its tracked state.
An existing journal entry discovered by a recreated coordinator requires
reconciliation rather than a blind resubmission.

Local actor isolation is not distributed idempotency. A real backend must
enforce uniqueness and reject reuse with conflicting payloads.

Acceptance is not settlement.

## Reconciliation and Recovery

TransferReconciliationService performs bounded status lookups using the
journaled intent identity and idempotency key.

Unavailable, pending, or not-found responses do not establish rejection.
The service does not submit transfers.

Status ordering uses server-defined versions when supplied. Stale responses
cannot replace a newer accepted snapshot, and conflicting equal versions
are rejected.

Retain the reconciliation service to preserve its ordering knowledge.
Its snapshots are process-local and do not update the journal.

TransferRecoveryService enumerates journal entries and reconciles them.
It does not delete entries or guarantee background execution.

## Approval and Security

Approval state is separate from transfer financial state.

The simulated approval backend validates membership, organization, maker
and checker separation, decision revision, and the approved payload.
Local roles and approval snapshots are not authoritative credentials.

StepUpTransferGateway checks the local session before and after
authentication. It forwards the request only when its local conditions hold.

Keychain storage and LocalAuthentication do not replace server-side
authentication, authorization, limits, or transaction validation.

## Observability

Diagnostic events contain allowlisted names and an ephemeral correlation UUID.

Diagnostics are best-effort and cannot replace a business result.
The OSLog adapter does not record transfer payloads, tokens, intent IDs,
or idempotency keys.

Current instrumentation covers submission orchestration. It is not a
complete distributed trace or financial audit log.

## Quality Goals and Trade-offs

| Goal | Decision and limit |
|---|---|
| Reliability | Persist before sending and preserve uncertainty; backend durability remains outside the client |
| Scalability | Isolate adapters behind ports; no distributed throughput claim is made |
| Testability | Inject gateways, storage, clocks, identifiers, delays, and authentication |
| Maintainability | Use explicit lifecycle rules, typed failures, and focused modules |
| Modularity | Keep Apple framework adapters outside the domain |
| Extensibility | Add adapters against existing contracts; do not invent unsupported payment rails |
| Security | Keep financial authority on the server; local checks remain bypassable on an untrusted client |

## Decisions and Evidence

- [Lifecycle](ADR-001-transfer-lifecycle.md)
- [Idempotency boundary](ADR-002-idempotency-boundary.md)
- [Crash recovery](ADR-003-crash-recovery.md)
- [Status ordering](ADR-004-status-version-ordering.md)
- [Security boundaries](ADR-005-security-boundaries.md)
- [Observability privacy](ADR-006-observability-privacy.md)
- [Failure scenario matrix](FailureScenarioMatrix.md)

Test source and architecture documents describe intended behavior.
Execution results must be recorded separately.
