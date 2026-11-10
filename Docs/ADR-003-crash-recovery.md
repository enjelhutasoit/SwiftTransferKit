# ADR-003: Relaunch Recovery by Durable Identity

- Status: Accepted
- Scope: Journal enumeration and recovery orchestration
- Release milestone: v0.3.0

## Context

The application may stop after saving an intent but before sending it,
or after server acceptance but before receiving the response.

After relaunch, in-memory coordinator state is unavailable.
The durable journal retains intent identity, payload, and idempotency key.

The current journal does not persist authoritative financial status.

## Decision

Add TransferRecoveryJournal as an enumeration capability extending
TransferJournal. Existing TransferJournal conformers remain compatible.

CoreDataTransferJournal returns value snapshots from its context queue.
The persistent model and existing store schema remain unchanged.

TransferRecoveryService scans the journal and reconciles each intent
using the existing status-query service.

Recovery has no submission dependency and never generates new identity
or idempotency keys.

Results are classified as:

- Unresolved: no trustworthy financial disposition was obtained.
- Processing: the server confirmed acceptance.
- Completed: the server confirmed settlement or rejection.

Completed does not mean successful settlement in every case.
The reconciliation result retains the exact state.

## Crash Windows

### Saved before submission

The server may return not found. Recovery preserves the original
journal entry and reports unresolved. It does not submit automatically.

### Accepted before response delivery

The status query can discover acceptance using the persisted identity.
Recovery does not create another transfer.

## Startup Coordination

The host retains one recovery service instance and invokes it on
launch or activation.

Only one pass runs at a time per service instance.
A concurrent invocation receives recoveryInProgress.

Cancellation releases the reservation for a later pass.
Background execution and automatic OS scheduling are not guaranteed.

## Failure Behavior

Status outages produce unresolved candidates and preserve the journal.

A journal scan/read failure aborts the report instead of returning
an apparently complete empty or partial result.

Recovery never updates or deletes journal entries.
A later pass can safely query them again.

## Trade-offs and Limitations

All journaled intents are queried, including potentially completed ones,
because financial status is not persisted in the current journal.

Results are observations returned to the host, not durable lifecycle
updates or mutations of the submission coordinator's cache.

The scan loads all entries into memory. Queries run sequentially.
Attempt limits apply per intent, not to the total pass duration.

Entries added after the scan may be discovered on the next pass.

UUID sorting provides stable traversal only. It does not establish
financial event ordering.

Server-version ordering belongs to Commit 10.

Tests reopen the same SQLite journal using new instances and model
crash boundaries. They do not terminate a real application process.

No real-money, production banking, or compliance guarantee is made.

## Verification

Cover both crash windows, completed transfers without resubmission,
status outage preservation, scan failure, concurrent recovery,
and cancellation cleanup.

Record actual build and test results in 04_PROGRESS.md.
