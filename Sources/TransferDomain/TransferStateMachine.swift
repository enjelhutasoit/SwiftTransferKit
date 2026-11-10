//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum TransferStateMachine {
    public enum TransitionError: Error, Equatable, Sendable {
        case invalidTransition(state: TransferState, event: TransferEvent)
    }

    public enum StatusUpdateError: Error, Equatable, Sendable {
        case nonAuthoritativeState
        case missingVersion
        case conflictingVersion(TransferStatusVersion)
    }

    /// Evaluates a lifecycle event without mutating the caller's state.
    public static func transition(
        from state: TransferState,
        on event: TransferEvent
    ) throws -> TransferState {
        switch (state, event) {
        case (.created, .submissionStarted),
             (.submitting, .submissionStarted):
            return .submitting

        case (.submitting, .submissionTimedOut),
             (.unknown, .submissionTimedOut):
            return .unknown

        case (.submitting, .serverAccepted),
             (.unknown, .serverAccepted),
             (.accepted, .serverAccepted):
            return .accepted

        case (.submitting, .serverSettled),
             (.unknown, .serverSettled),
             (.accepted, .serverSettled),
             (.settled, .serverSettled):
            return .settled

        case (.submitting, .serverRejected),
             (.unknown, .serverRejected),
             (.accepted, .serverRejected),
             (.rejected, .serverRejected):
            return .rejected

        case (.accepted, .submissionTimedOut),
             (.settled, .submissionTimedOut),
             (.rejected, .submissionTimedOut):
            return state

        default:
            throw TransitionError.invalidTransition(state: state, event: event)
        }
    }

    /// Merges one financial observation without mutating either input.
    ///
    /// Older observations are ignored. Equal-version conflicts throw.
    /// Newer observations must still satisfy the lifecycle.
    public static func applying(
        _ incoming: TransferStatusSnapshot,
        to current: TransferStatusSnapshot?
    ) throws -> TransferStatusSnapshot {
        let event: TransferEvent

        switch incoming.state {
        case .accepted:
            event = .serverAccepted
        case .settled:
            event = .serverSettled
        case .rejected:
            event = .serverRejected
        case .created, .submitting, .unknown:
            throw StatusUpdateError.nonAuthoritativeState
        }

        if let current, let currentVersion = current.version {
            guard let incomingVersion = incoming.version else {
                throw StatusUpdateError.missingVersion
            }

            if incomingVersion < currentVersion {
                return current
            }

            if incomingVersion == currentVersion {
                guard incoming.state == current.state else {
                    throw StatusUpdateError.conflictingVersion(
                        incomingVersion
                    )
                }

                return current
            }
        }

        let state = try transition(
            from: current?.state ?? .unknown,
            on: event
        )

        return TransferStatusSnapshot(
            state: state,
            version: incoming.version
        )
    }
}
