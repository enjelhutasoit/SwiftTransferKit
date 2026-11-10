//
// Copyright (c) 2026 Enjel Hutasoit
//

import CoreData
import Foundation
import TransferCore
import TransferDomain

public actor CoreDataTransferJournal: TransferRecoveryJournal {
    private let controller: TransferPersistenceController

    public init(storeURL: URL) throws {
        controller = try TransferPersistenceController(storeURL: storeURL)
    }

    init(storeURL: URL, readOnly: Bool) throws {
        controller = try TransferPersistenceController(
            storeURL: storeURL,
            readOnly: readOnly
        )
    }

    public func record(
        _ intent: TransferIntent,
        idempotencyKey: UUID
    ) async throws -> JournaledTransfer {
        try await controller.perform { context in
            if let existing = try Self.existingEntry(
                matching: intent,
                in: context
            ) {
                return existing
            }

            let entry = JournaledTransfer(
                intent: intent,
                idempotencyKey: idempotencyKey
            )
            try TransferRecord.insert(entry, into: context)

            do {
                try context.save()
                return entry
            } catch {
                context.reset()

                // Another writer may have committed this intent first.
                if let existing = try Self.existingEntry(
                    matching: intent,
                    in: context
                ) {
                    return existing
                }

                if try Self.fetch(
                    attribute: "idempotencyKey",
                    value: idempotencyKey,
                    in: context
                ) != nil {
                    throw TransferJournalError.idempotencyKeyConflict
                }

                throw TransferJournalError.storageFailure
            }
        }
    }

    public func entry(for intentID: UUID) async throws -> JournaledTransfer? {
        try await controller.perform { context in
            let record = try Self.fetch(
                attribute: "intentID",
                value: intentID,
                in: context
            )
            return try record?.value()
        }
    }

    public func allEntries() async throws -> [JournaledTransfer] {
        try await controller.perform { context in
            let request = NSFetchRequest<TransferRecord>(
                entityName: TransferRecord.entityName
            )
            let records = try context.fetch(request)
            let entries = try records.map { try $0.value() }

            // Stable traversal only; UUID ordering has no financial meaning.
            return entries.sorted {
                $0.intent.id.uuidString < $1.intent.id.uuidString
            }
        }
    }

    private static func existingEntry(
        matching intent: TransferIntent,
        in context: NSManagedObjectContext
    ) throws -> JournaledTransfer? {
        guard let record = try fetch(
            attribute: "intentID",
            value: intent.id,
            in: context
        ) else {
            return nil
        }

        let existing = try record.value()
        guard existing.intent == intent else {
            throw TransferJournalError.intentConflict
        }

        return existing
    }

    private static func fetch(
        attribute: String,
        value: UUID,
        in context: NSManagedObjectContext
    ) throws -> TransferRecord? {
        let request = NSFetchRequest<TransferRecord>(
            entityName: TransferRecord.entityName
        )
        request.predicate = NSPredicate(
            format: "%K == %@",
            attribute,
            value as NSUUID
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
