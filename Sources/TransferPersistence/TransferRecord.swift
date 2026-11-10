//
// Copyright (c) 2026 Enjel Hutasoit
//

import CoreData
import Foundation
import TransferCore
import TransferDomain

@objc(STKTransferRecord)
final class TransferRecord: NSManagedObject {
    static let entityName = "TransferRecord"

    @NSManaged var intentID: UUID?
    @NSManaged var idempotencyKey: UUID?
    @NSManaged var minorUnits: Int64
    @NSManaged var currencyCode: String?
    @NSManaged var scale: Int16

    func value() throws -> JournaledTransfer {
        guard let intentID,
              let idempotencyKey,
              let currencyCode else {
            throw TransferJournalError.corruptRecord
        }

        let amount: Money
        do {
            amount = try Money(
                minorUnits: minorUnits,
                currencyCode: currencyCode,
                scale: Int(scale)
            )
        } catch {
            throw TransferJournalError.corruptRecord
        }

        return JournaledTransfer(
            intent: TransferIntent(id: intentID, amount: amount),
            idempotencyKey: idempotencyKey
        )
    }

    static func insert(
        _ entry: JournaledTransfer,
        into context: NSManagedObjectContext
    ) throws {
        guard let entity = NSEntityDescription.entity(
            forEntityName: entityName,
            in: context
        ) else {
            throw TransferJournalError.storageFailure
        }

        let record = TransferRecord(entity: entity, insertInto: context)
        record.intentID = entry.intent.id
        record.idempotencyKey = entry.idempotencyKey
        record.minorUnits = entry.intent.amount.minorUnits
        record.currencyCode = entry.intent.amount.currency.rawValue
        record.scale = Int16(entry.intent.amount.currency.minorUnitScale)
    }

    static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = entityName
        entity.managedObjectClassName = NSStringFromClass(TransferRecord.self)
        entity.properties = [
            attribute("intentID", type: .UUIDAttributeType),
            attribute("idempotencyKey", type: .UUIDAttributeType),
            attribute("minorUnits", type: .integer64AttributeType),
            attribute("currencyCode", type: .stringAttributeType),
            attribute("scale", type: .integer16AttributeType),
        ]
        entity.uniquenessConstraints = [
            ["intentID"],
            ["idempotencyKey"],
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        model.versionIdentifiers = ["TransferJournalV1"]
        return model
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = false
        return attribute
    }
}
