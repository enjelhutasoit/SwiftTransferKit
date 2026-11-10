//
// Copyright (c) 2026 Enjel Hutasoit
//

/// One-shot response faults for the in-process simulator.
public enum SimulatedBankFault: Sendable {
    /// Accepts the transfer, then reports a lost response as a timeout.
    case timeoutAfterCommit

    /// Accepts the transfer, then waits for the supplied operation to return.
    ///
    /// The caller controls release; no wall-clock delay is imposed.
    case delayedResponse(@Sendable () async -> Void)
}

/// Simulator diagnostics without raw request payloads.
public enum SimulatedBankError: Error, Equatable, Sendable {
    case timedOut
    case idempotencyKeyConflict
    case intentConflict
}
