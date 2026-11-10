# ADR-001 — Authoritative Transfer Lifecycle

## Status

Accepted for the simulated SDK design.

## Context

A submission can reach the server even when its response is lost.
The client therefore needs an explicit unresolved state.

Server acceptance confirms that processing has begun.
Settlement requires a separate authoritative outcome.

## Decision

Represent the lifecycle with six states.

- created
- submitting
- unknown
- accepted
- settled
- rejected

Use a pure transition function that returns the next state or throws
an invalid-transition error.

A submission timeout moves submitting to unknown.
Repeated timeouts preserve unknown.

Server responses can resolve submitting or unknown directly to
accepted, settled, or rejected. Intermediate responses may be missed.

An accepted transfer can subsequently settle or be rejected by the server.

Repeated matching server events preserve the current state.
A repeated submission-start event preserves submitting.

A timeout received after accepted, settled, or rejected preserves
the last known server state.

Settled and rejected are terminal. Conflicting events are rejected.
Invalid transitions leave the caller responsible for retaining its
existing state and handling the error.

Integration code must associate each event with the correct intent
and emit server events only from authoritative responses.

## Consequences

The lifecycle explicitly represents uncertainty.

The transition function is deterministic and independently testable.
Callers own state storage and synchronization.

The current rules reject invalid regressions and conflicting terminal
outcomes. Server-issued status version handling is scheduled for
Commit 10.

Reversals require a separate linked operation.

## Verification

XCTest covers all 30 combinations of the six states and five events.
Execution results must be recorded in the progress ledger.

## Scope

This is a simulated educational SDK lifecycle.
Backend processing and financial authorization remain authoritative.
