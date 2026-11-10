# ADR-002: Client Coordination and Backend Idempotency Boundaries

- Status: Accepted
- Scope: Simulated transfer submission
- Release milestone: v0.2.0

## Context

A client can lose a response after a server accepts a transfer.
Duplicate taps, repeated requests, and independent client instances
must not be confused with new business intent.

An actor protects state within its isolation domain. It does not
establish uniqueness across devices, processes, or backend replicas.

## Decision

The client journals intent identity and an idempotency key before
submission. The coordinator uses the journal-returned key.

The coordinator suppresses repeated submissions within its lifetime.
Unknown outcomes are preserved without automatic resubmission.

A separate TransferSimulation module models a server-side uniqueness
boundary using a shared, in-memory actor store.

The simulated store applies these rules:

- Same key and identical transfer: return the existing acceptance.
- Same key and different transfer: throw an idempotency-key conflict.
- Same intent ID and a different key: throw an intent conflict.
- Conflict attempts do not replace an accepted record.

Uniqueness checks and insertion execute without suspension.

Response faults occur after acceptance:

- Timeout after commit preserves the accepted record.
- Delayed response waits for an explicitly controlled release.

Faults are configured per key and consumed by the first attempt using
that key on the configured gateway instance. Store validation takes
precedence over response fault delivery.

## Consequences

Direct simulator replay tests verify simulated server behavior.
They do not authorize automatic client retries of unknown transfers.

The simulator can demonstrate that the client sees unknown while
the simulated server already holds an accepted transfer.

Acceptance does not establish settlement, debit, or credit.

Production SDK targets do not depend on TransferSimulation.
Tests and the future demo may explicitly depend on it.

## Limitations

The store is process-local, memory-only, and unbounded.
Independent stores do not share uniqueness guarantees.

No balances, ledger, real payment rails, database transactions,
distributed consistency, or production banking integration are modeled.

A real backend must enforce durable idempotency atomically at the
appropriate transaction boundary. This simulator does not prove it.

## Verification

Behavioral tests cover concurrent replay, payload/key conflicts,
timeout after commit, controlled response delay, and coordinator
integration with the Core Data journal.

Record actual test and build results in 04_PROGRESS.md.
