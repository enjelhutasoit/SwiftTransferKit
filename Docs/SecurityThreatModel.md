# Security Threat Model

This document describes a simulated SDK and its trust boundaries.
It is not a security certification or compliance assessment.

## Assets

- Session credentials.
- Stable transfer intent identity and idempotency keys.
- Journaled transfer payloads.
- Approval identity, revision, and decision.
- Authoritative financial state.
- Diagnostic confidentiality.

## Trust Boundaries

The application, local storage, and local authentication are client-side
components. A compromised client can bypass their checks.

A real backend must authenticate the caller and independently validate
organization membership, permissions, approvals, limits, payload identity,
idempotency, and financial state.

The in-process simulated backend models selected checks. It is not a
security boundary against the application process.

## Threats and Controls

| Threat | Current control | Remaining responsibility or limitation |
|---|---|---|
| Duplicate submission | Stable journaled identity and simulated backend uniqueness | A real backend must enforce durable idempotency |
| Changed payload under an existing identity | Journal and simulated backend conflict checks | Real server validation is required |
| Forged local approval or role | Simulated backend checks stored approval and membership | Local metadata is not an authentication credential |
| Session expiration during authentication | Session validation before and after step-up | Server-side expiry and revocation remain required |
| Credential exposure in diagnostics | Typed diagnostic events and credential redaction | Hosts must not log explicit token access or encoded credentials |
| Local credential theft | Device-only, non-synchronizing Keychain storage accessible when unlocked | No protection claim for a fully compromised process |
| Redirecting submission traffic | HTTPS endpoint validation and redirect rejection | No certificate pinning or complete backend security integration |
| Stale status response | Server-version ordering and conflict detection | Ordering snapshots are not persisted across process recreation |
| Journal tampering | Record validation and identity conflict detection | No application-level authenticated journal encryption |
| Diagnostic sink failure | Best-effort diagnostic emission | Diagnostics are not a durable audit trail |

## Credential Handling

KeychainCredentialStore uses a scoped generic-password item with
device-only accessibility while unlocked.

Session credentials expose raw token access explicitly for transport.
Their encoded representation contains sensitive data and must not be logged.

The project does not claim memory zeroization, automatic token refresh,
remote revocation, or biometric access control on every Keychain read.

The HTTP submission adapter currently does not attach session credentials.

## Local Authentication

LocalBiometricAuthenticator uses LocalAuthentication for local biometric
verification. It does not silently fall back to a device passcode.

A successful prompt establishes local user presence only.
It does not prove bank authorization or cryptographically bind a transaction.

The host application must supply NSFaceIDUsageDescription when using Face ID.

Automated tests use authentication doubles. They do not validate real
biometric hardware.

## Data and Logging

The Core Data journal contains transfer metadata.
Do not store real financial information in this demonstration.

No journal retention policy, secure deletion guarantee, or encrypted
database layer is provided.

Diagnostic events must not include credentials, account data, transfer
amounts, intent IDs, or idempotency keys.

## Exclusions

This project does not implement payment rails, a ledger, fraud detection,
regulatory controls, production identity infrastructure, or banking
certification.
