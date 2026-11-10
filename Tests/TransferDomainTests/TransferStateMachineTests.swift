//
// Copyright (c) 2026 Enjel Hutasoit
//

import TransferDomain
import XCTest

final class TransferStateMachineTests: XCTestCase {
    func testSubmissionStartsAndDuplicateStartPreservesSubmitting() throws {
        let started = try TransferStateMachine.transition(
            from: .created,
            on: .submissionStarted
        )
        let repeated = try TransferStateMachine.transition(
            from: started,
            on: .submissionStarted
        )

        XCTAssertEqual(started, .submitting)
        XCTAssertEqual(repeated, .submitting)
    }

    func testTimeoutProducesAndPreservesUnknownOutcome() throws {
        let timedOut = try TransferStateMachine.transition(
            from: .submitting,
            on: .submissionTimedOut
        )
        let repeated = try TransferStateMachine.transition(
            from: timedOut,
            on: .submissionTimedOut
        )

        XCTAssertEqual(timedOut, .unknown)
        XCTAssertEqual(repeated, .unknown)
    }

    func testServerUpdatesResolveSubmittingAndUnknownStates() throws {
        let states: [TransferState] = [.submitting, .unknown]
        let outcomes: [(TransferEvent, TransferState)] = [
            (.serverAccepted, .accepted),
            (.serverSettled, .settled),
            (.serverRejected, .rejected)
        ]

        for state in states {
            for (event, expectedState) in outcomes {
                let result = try TransferStateMachine.transition(
                    from: state,
                    on: event
                )

                XCTAssertEqual(result, expectedState, "\(state), \(event)")
            }
        }
    }

    func testAcceptedTransferCanSettleOrBeRejectedByServer() throws {
        let outcomes: [(TransferEvent, TransferState)] = [
            (.serverSettled, .settled),
            (.serverRejected, .rejected)
        ]

        for (event, expectedState) in outcomes {
            let result = try TransferStateMachine.transition(
                from: .accepted,
                on: event
            )

            XCTAssertEqual(result, expectedState, "\(event)")
        }
    }

    func testDuplicateServerUpdatesPreserveCurrentState() throws {
        let duplicates: [(TransferState, TransferEvent)] = [
            (.accepted, .serverAccepted),
            (.settled, .serverSettled),
            (.rejected, .serverRejected)
        ]

        for (state, event) in duplicates {
            let result = try TransferStateMachine.transition(
                from: state,
                on: event
            )

            XCTAssertEqual(result, state, "\(state), \(event)")
        }
    }

    func testLateTimeoutPreservesLastKnownServerState() throws {
        let states: [TransferState] = [.accepted, .settled, .rejected]

        for state in states {
            let result = try TransferStateMachine.transition(
                from: state,
                on: .submissionTimedOut
            )

            XCTAssertEqual(result, state, "\(state)")
        }
    }

    func testInvalidTransitionsReportTheRejectedStateAndEvent() {
        let invalidTransitions: [(TransferState, TransferEvent)] = [
            (.created, .submissionTimedOut),
            (.created, .serverAccepted),
            (.created, .serverSettled),
            (.created, .serverRejected),
            (.unknown, .submissionStarted),
            (.accepted, .submissionStarted),
            (.settled, .submissionStarted),
            (.settled, .serverAccepted),
            (.settled, .serverRejected),
            (.rejected, .submissionStarted),
            (.rejected, .serverAccepted),
            (.rejected, .serverSettled)
        ]

        for (state, event) in invalidTransitions {
            XCTAssertThrowsError(
                try TransferStateMachine.transition(from: state, on: event)
            ) { error in
                XCTAssertEqual(
                    error as? TransferStateMachine.TransitionError,
                    .invalidTransition(state: state, event: event)
                )
            }
        }
    }
}
