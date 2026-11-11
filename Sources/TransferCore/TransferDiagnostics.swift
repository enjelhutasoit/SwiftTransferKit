//
// Copyright (c) 2026 Enjel Hutasoit
//

/// Receives best-effort diagnostic events.
///
/// Implementations must return promptly and must not perform blocking
/// network I/O or synchronously wait for the calling coordinator.
///
/// Thrown errors must not influence financial state or persistence.
public protocol TransferDiagnostics: Sendable {
    func record(_ event: TransferDiagnosticEvent) throws
}

/// Default behavior: no diagnostic output.
public struct NoOpTransferDiagnostics: TransferDiagnostics {
    public init() {}

    public func record(_ event: TransferDiagnosticEvent) {}
}
