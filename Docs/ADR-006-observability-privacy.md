# ADR-006: Privacy-Safe Submission Diagnostics

- Status: Accepted
- Scope: Commit 14
- Release milestone: v0.4.0

## Context

Submission incidents need an observable sequence of events.

Diagnostics must not expose credentials, account identifiers, amounts,
idempotency keys, request bodies, response bodies, or raw errors.

Client logs cannot establish authoritative financial state or serve as
a financial audit trail.

## Decision

Define a synchronous, Sendable TransferDiagnostics port in TransferCore.

Use NoOpTransferDiagnostics by default.

Provide an optional OSLogTransferDiagnostics adapter in TransferObservability.

Instrument coordinator submission, persistence preparation, reuse, conflicts,
authoritative submission responses, and unresolved outcomes.

## Event Schema

The public payload contains exactly:

- name: an allowlisted enum value.
- correlationID: an opaque UUID.

Do not accept arbitrary messages or metadata dictionaries.

Generate correlation IDs independently from intent IDs and idempotency keys.

Injected correlation generators must also return fresh opaque IDs and must
not derive them from user, account, credential, or financial identifiers.

## Correlation Scope

One tracked submission keeps one correlation ID within a coordinator.

Repeated calls for that tracked intent reuse its correlation ID.

Correlation IDs are not persisted or sent to the backend.

A new coordinator or a new attempt after preparation failure may use a new ID.

This commit does not instrument reconciliation polling or provide cross-launch
or distributed tracing.

## Logging Privacy

The OSLog adapter uses a fixed subsystem and category.

Event names are public. Correlation IDs use private hash masking.

The event schema excludes sensitive payload before it reaches any sink.

OSLog controls how private values are displayed under the active logging
configuration. Masked hashes are process-local and are not durable identifiers.

## Failure Isolation

Coordinator state and business results do not depend on successful logging.

Thrown sink errors are discarded without recursive logging.

The synchronous port adds no suspension points to coordinator state mutations.

Sinks must return promptly and must not block on network I/O or synchronously
wait for the coordinator. Error isolation is not a latency guarantee.

## Verification

Deterministic tests verify:

- Ordered submission events with a shared correlation ID.
- Correlation reuse without duplicate gateway submission.
- A two-field payload allowlist with sensitive values absent.
- Unchanged accepted, rejected, and unknown results when the sink throws.
- Preservation of persistence errors when diagnostics also fail.
- Existing journal entries requiring reconciliation without submission.

The OSLog adapter is verified by Apple-platform compilation and source review.
Unit tests do not assert operating-system log retention or rendered masking.

## Consequences

Diagnostics remain optional and require no paid service or third-party package.

The limited schema reduces diagnostic detail.

Events can be absent or lost. Missing events do not prove that a business action
did not happen. Client logs are not authoritative audit records.
