//
// Copyright (c) 2026 Enjel Hutasoit
//

public enum TransferStateMachine {
    public enum TransitionError: Error, Equatable, Sendable {
        case invalidTransition(state: TransferState, event: TransferEvent)
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
}
