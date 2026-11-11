# ADR-005: Local Session and Step-Up Boundaries

- Status: Accepted
- Scope: Commit 12
- Release milestone: v0.4.0

## Context

Transfer submission needs stronger local assurance than read-only access.

Local session metadata and biometrics cannot establish backend authorization,
payment acceptance, settlement, or regulatory compliance.

The SDK must preserve persisted intent identity when local authentication fails.

## Decision

Add a TransferSecurity module with:

- An injectable credential store.
- A session provider with an injectable clock.
- A service/account-scoped Keychain credential store.
- An injectable step-up authenticator.
- A MainActor-isolated LocalAuthentication adapter.
- A TransferGateway decorator that enforces local checks.

The gateway decorator validates the expected user and organization before
step-up, then reloads and validates the credential after step-up.

A changed, missing, or expired credential blocks the underlying gateway.

Session expiry is exclusive: a credential is expired when now equals expiresAt.

## Keychain Storage

Use a generic-password item identified by service and account.

Use kSecAttrAccessibleWhenUnlockedThisDeviceOnly, disable synchronization,
and select the Data Protection Keychain.

Update existing items before attempting insertion. Do not delete before saving.

Deletion is scoped to the configured service and account.

This configuration does not impose a biometric access-control requirement on
each Keychain read. Biometric step-up is a separate application-level gate.

## Local Authentication

Use deviceOwnerAuthenticationWithBiometrics.

Use a new LAContext for each attempt and disable Touch ID reuse.

Do not silently fall back to device passcode authentication.

Reject overlapping attempts on the same authenticator instance.

Invalidate the matching context when its task is cancelled.

The host application owns NSFaceIDUsageDescription and prompt localization.

## Privacy

Redact ordinary string, debug, and mirror representations of credentials.

Map credential-store failures and unexpected authenticator failures to typed
errors without forwarding their original messages.

Explicit transport access and encoded credential data contain the token.
They must never be logged.

This design does not guarantee memory zeroization or prevent a debugger from
accessing process memory.

## Integration

TransferCoordinator persists intent and idempotency key before calling its
gateway. The security decorator therefore cannot erase the intent when
authentication fails.

The current coordinator maps all gateway errors to unknown. This includes
local authentication failures, even when the underlying gateway was not called.

Commit 13 owns the planned failure taxonomy. This commit does not change the
coordinator's financial-state contract or introduce automatic resubmission.

The decorator does not attach an HTTP Authorization header, implement login,
refresh tokens, or turn the simulated backend into a production integration.

## Authority

The backend must validate credentials, revocation, organization membership,
permissions, approvals, and transfer policy.

Local expiry uses the client clock and is an advisory check.

Checks before submission are not atomic with logout or server revocation.

Local biometric success is not transaction signing or backend authorization.

## Verification

Deterministic tests cover:

- Valid, missing, expired, and mismatched sessions.
- Credential diagnostic redaction and sanitized store errors.
- Successful step-up forwarding the original transfer.
- Failed or cancelled step-up blocking submission.
- Expiry, replacement, and logout during step-up.
- Durable intent preservation when an expired session blocks submission.

Tests use injected credential stores and authenticators.

Native Keychain behavior, biometric prompts, and native cancellation require
host-application verification. Unit tests do not claim to verify these adapters
against the operating system.

## Consequences

The SDK gains explicit local security boundaries without changing domain types.

Keychain credentials are unavailable while the device is locked.

Biometrics-only authentication excludes devices without available biometrics.

Backend authorization remains mandatory, including after local checks succeed.
