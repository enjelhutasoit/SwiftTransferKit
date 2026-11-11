//
// Copyright (c) 2026 Enjel Hutasoit
//

import OSLog
import TransferCore

/// Writes allowlisted events to Apple Unified Logging.
///
/// Correlation values use private hash masking.
/// No transfer payload, raw error, or credential is accepted.
public struct OSLogTransferDiagnostics: TransferDiagnostics {
    public init() {}

    public func record(_ event: TransferDiagnosticEvent) {
        let logger = Logger(
            subsystem: "com.enjelhutasoit.swifttransferkit",
            category: "TransferSubmission"
        )

        logger.info(
            "event=\(event.name.rawValue, privacy: .public) correlation=\(event.correlationID.uuidString, privacy: .private(mask: .hash))"
        )
    }
}
