# ADR-004: Server-Version Status Ordering

- Status: Accepted
- Scope: Reconciliation observations
- Release milestone: v0.3.0

## Decision

Order financial status observations by a server-issued revision scoped
to one intent identity. Do not use client timestamps or response arrival
order as financial authority.

For a known versioned snapshot:

- Lower version: retain the current snapshot.
- Equal version and equal state: retain the current snapshot.
- Equal version and different state: throw a conflict.
- Higher version: validate the lifecycle before applying.
- Missing version: throw instead of downgrading the version contract.

Pending, not-found, and transport failures do not replace the financial
snapshot or advance its revision.

A higher version cannot bypass lifecycle rules. A settled transfer
cannot become rejected as a representation of reversal. A reversal
requires a separate linked business operation, which is outside this
implementation.

## Isolation

TransferReconciliationService is an actor.
Snapshot comparison and mutation contain no suspension point.

Ordering knowledge is retained by one service instance.
The host must retain that instance for the relevant flow.

## Compatibility

TransferStatusResponse accepts an optional version for source
compatibility with existing adapters.

Unversioned observations retain lifecycle validation, but do not gain
version-ordering guarantees. The client never synthesizes their version.

Once versioned observations exist for an intent, unversioned financial
observations cannot replace them.

ReconciliationResult remains source-compatible.
latestStatus(for:) exposes the current state and optional version.

## Simulator

The shared simulated store owns lifecycle revisions.
Acceptance starts at revision 1.
A valid lifecycle change increments the revision.
Duplicate submission or repeating the same state does not increment it.

Submission replay returns the original acceptance acknowledgement.
Status lookup returns the current lifecycle state and revision.

## Limitations

Snapshots and version watermarks are memory-only.
They are not shared across service instances or retained after relaunch.

The durable journal still preserves identity, payload, and key.
It does not persist financial status versions.

Returned values are snapshots, not a globally ordered UI event stream.
Consumers must not interpret task completion order as version order.

No real settlement, reversal, ledger, or banking integration is implemented.
