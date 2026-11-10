//
// Copyright (c) 2026 Enjel Hutasoit
//

/// Adds snapshot enumeration without changing existing journal conformers.
public protocol TransferRecoveryJournal: TransferJournal {
    /// Returns the entries visible during this scan.
    ///
    /// Entries added afterward may be discovered by the next recovery pass.
    func allEntries() async throws -> [JournaledTransfer]
}
