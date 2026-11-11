# Failure Scenario Matrix

This matrix records intended coverage, not proof of successful execution.

All new Commit 16 tests require execution on the supported Apple toolchain.

## Integration Coverage

| Scenario | Test | Required invariant |
|---|---|---|
| Duplicate while an accepted response is held | DuplicateSubmissionTests.test_duplicateWhileAcceptedResponseIsHeld_doesNotSubmitAgain | One forwarded submission and one simulated acceptance |
| Response lost, followed by status outage | AmbiguousOutcomeTests.test_timeoutThenOutage_preservesIdentityUntilSettlementIsConfirmed | Unresolved outcome, bounded lookups, stable identity, no resubmission |
| Older and duplicate server responses | AmbiguousOutcomeTests.test_replayedOlderAndDuplicateBankResponses_doNotRegressSettlement | Settlement and server version do not regress |
| Interruption after persistence but before send | CrashRecoveryTests.test_preparedButUnsentIntent_remainsUnresolvedAfterClientRecreation | Original key retained; not-found does not authorize resubmission |
| Unauthorized approval plus forged local snapshot | ApprovalWorkflowTests.test_unauthorizedDecision_cannotAuthorizeJournaledSubmission | Backend approval remains authoritative; no acceptance |
| Session expires after valid approval | ApprovalWorkflowTests.test_sessionExpiringAfterApproval_blocksSubmissionAndPreservesIntent | No step-up or underlying submission; durable intent retained |

## Existing Coverage Retained

| Scenario | Existing suite |
|---|---|
| Maker-checker through settlement | BusinessTransferWorkflowTests |
| Lost response followed by client recreation | BusinessTransferWorkflowTests |
| Rejected approval blocks demo submission | BusinessTransferWorkflowTests |
| Maker self-approval and cross-organization attempts | TransferApprovalTests |
| Concurrent approval decisions and stale approval revisions | TransferApprovalTests |
| Persistence failures block submission | TransferCoordinatorTests / TransferJournalTests |
| Same-version conflicts and invalid status transitions | TransferStatusOrderingTests |
| Step-up cancellation and session changes during authentication | StepUpAuthorizationTests |
| Diagnostics failures do not alter business results | TransferDiagnosticsTests |

## Execution

New Commit 16 test methods: 6.

Existing Commit 15 workflow test methods: 3.

Expected TransferIntegrationTests total: 9.

Record actual commands, results, toolchain versions, and failures in 04_PROGRESS.md.
Do not mark this matrix verified solely because the test source exists.

## Test Design

- Use a real temporary Core Data journal.
- Use the in-process simulated bank.
- Hold responses using continuations, not timing sleeps.
- Use an XCTest timeout only as a failure bound for the expected concurrency event.
- Inject clocks and retry delays.
- Observe public results, journal entries, submitted requests, and simulated acceptance count.
- Do not use real network requests, Keychain access, or biometrics.

## Limits

Client recreation models selected interruption boundaries; it is not an OS
process-kill test.

The simulated bank remains in memory unless a test explicitly creates a new one.

These tests do not establish real payment safety, backend durability,
regulatory compliance, or production banking readiness.
