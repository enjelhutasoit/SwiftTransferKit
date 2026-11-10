//
// Copyright (c) 2026 Enjel Hutasoit
//

import CoreData
import Foundation
import TransferCore

/// Owns a private context accessed exclusively through its queue.
/// Only Sendable values may leave a performed operation.
final class TransferPersistenceController: @unchecked Sendable {
    private let context: NSManagedObjectContext

    init(storeURL: URL, readOnly: Bool = false) throws {
        guard storeURL.isFileURL else {
            throw TransferJournalError.storageFailure
        }

        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: TransferRecord.makeModel()
        )

        do {
            if !readOnly {
                try FileManager.default.createDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }

            _ = try coordinator.addPersistentStore(
                type: .sqlite,
                at: storeURL,
                options: [
                    NSReadOnlyPersistentStoreOption: readOnly,
                    NSSQLitePragmasOption: ["synchronous": "FULL"],
                ]
            )
        } catch {
            throw TransferJournalError.storageFailure
        }

        context = NSManagedObjectContext(
            concurrencyType: .privateQueueConcurrencyType
        )
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergePolicy.error
        context.undoManager = nil
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> Value
    ) async throws -> Value {
        do {
            return try await context.perform {
                defer { self.context.reset() }
                return try operation(self.context)
            }
        } catch let error as TransferJournalError {
            throw error
        } catch {
            throw TransferJournalError.storageFailure
        }
    }
}
