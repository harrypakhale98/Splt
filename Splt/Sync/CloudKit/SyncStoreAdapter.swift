import CloudKit
import Foundation
import SwiftData

/// Joins the data layer and CloudKit without touching the network. It reads what changed locally,
/// builds the records to send, and applies what came back, so the whole round trip can be tested
/// with in memory records.
@MainActor
final class SyncStoreAdapter {
    let tracker: ChangeTracker
    private(set) var metadata: SyncMetadata
    let store: any SyncStateStore
    private var knownTypes: [CKRecord.ID: SyncRecordType] = [:]
    /// Who last saved a record, as the server reports it. A seam for tests: a record built on the device has no author.
    var lastModifier: (CKRecord) -> String? = { $0.lastModifiedUserRecordID?.recordName }

    init(tracker: ChangeTracker, store: any SyncStateStore) {
        self.tracker = tracker
        self.store = store
        self.metadata = store.loadMetadata()
    }

    func replaceMetadata(_ new: SyncMetadata) {
        metadata = new
        store.saveMetadata(new)
    }

    func updateMetadata(_ change: (inout SyncMetadata) -> Void) {
        var copy = metadata
        change(&copy)
        guard copy != metadata else { return }
        metadata = copy
        store.saveMetadata(copy)
    }

    // MARK: Outgoing

    /// Works out what to send. Person records are copied into every zone that mentions them.
    func collectOutgoing() throws -> OutgoingPlan {
        var plan = OutgoingPlan()
        let changes = try tracker.pendingChanges()
        var retired: Set<String> = []

        for change in changes where change.recordType == .group && change.operation == .delete {
            guard let zone = change.zoneName else { continue }
            retired.insert(zone)
            let id = metadata.zoneID(forZoneName: zone)
            if id.scope == .privateDatabase {
                plan.zonesToDelete.append(id)
            } else {
                plan.zonesToLeave.append(id)
            }
        }

        var references: [(zone: String, uuids: Set<String>)] = []
        var personChanges: [PendingChange] = []
        for change in changes {
            if change.recordType == .person {
                personChanges.append(change)
                continue
            }
            guard let zone = change.zoneName, !retired.contains(zone), !metadata.isDetached(zoneName: zone) else { continue }
            let id = RecordMapper.recordID(recordName: change.recordName, zoneID: metadata.zoneID(forZoneName: zone))
            knownTypes[id] = change.recordType
            switch change.operation {
            case .save:
                plan.saves.append(id)
                if let payload = try tracker.payload(recordType: change.recordType, recordName: change.recordName) {
                    references.append((zone, payload.fields.referencedUUIDs))
                }
            case .delete:
                plan.deletes.append(id)
            }
            if !metadata.isKnown(zoneName: zone), id.zoneID.scope == .privateDatabase, !plan.zonesToSave.contains(id.zoneID) {
                plan.zonesToSave.append(id.zoneID)
            }
        }

        try planPersonCopies(&plan, personChanges: personChanges, references: references, retired: retired)
        return plan
    }

    private func planPersonCopies(
        _ plan: inout OutgoingPlan, personChanges: [PendingChange],
        references: [(zone: String, uuids: Set<String>)], retired: Set<String>
    ) throws {
        let people = Dictionary(
            try tracker.context.fetch(FetchDescriptor<PersonRecord>()).map { ($0.recordName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var queue = metadata.personQueue
        for (zone, uuids) in references where !retired.contains(zone) {
            for name in uuids {
                guard let person = people[name], person.deletedAt == nil else { continue }
                if metadata.copyNeedsUpload(zoneName: zone, recordName: name, modifiedAt: person.modifiedAt) {
                    queue.insert(PersonCopyKey(zoneName: zone, recordName: name))
                }
            }
        }

        var deleting: Set<String> = []
        for change in personChanges {
            switch change.operation {
            case .save:
                let zones = (metadata.zonesHoldingCopy(of: change.recordName) + (try zonesOfMe(change.recordName, people: people)))
                    .filter { !retired.contains($0) }
                for zone in zones where metadata.copyNeedsUpload(
                    zoneName: zone, recordName: change.recordName, modifiedAt: change.modifiedAt
                ) {
                    queue.insert(PersonCopyKey(zoneName: zone, recordName: change.recordName))
                }
            case .delete:
                deleting.insert(change.recordName)
                let zones = metadata.privateZonesHoldingCopy(of: change.recordName).filter { !retired.contains($0) }
                for zone in zones {
                    plan.deletes.append(RecordMapper.recordID(
                        recordName: change.recordName, zoneID: metadata.zoneID(forZoneName: zone)
                    ))
                }
                queue = queue.filter { $0.recordName != change.recordName }
            }
        }

        queue = queue.filter { key in
            !retired.contains(key.zoneName) && people[key.recordName]?.deletedAt == nil && !deleting.contains(key.recordName)
                && people[key.recordName]?.hasNameToShare == true
        }
        for key in queue.sorted(by: { ($0.zoneName, $0.recordName) < ($1.zoneName, $1.recordName) }) {
            let id = RecordMapper.recordID(recordName: key.recordName, zoneID: metadata.zoneID(forZoneName: key.zoneName))
            knownTypes[id] = .person
            plan.saves.append(id)
            if !metadata.isKnown(zoneName: key.zoneName), id.zoneID.scope == .privateDatabase, !plan.zonesToSave.contains(id.zoneID) {
                plan.zonesToSave.append(id.zoneID)
            }
        }
        updateMetadata { $0.personQueue = queue }

        for change in personChanges {
            let waiting = queue.contains { $0.recordName == change.recordName }
            let removing = change.operation == .delete && !metadata.privateZonesHoldingCopy(of: change.recordName).isEmpty
            if !waiting && !removing {
                forgetCopies(of: change.recordName, onlyIf: change.operation == .delete)
                try tracker.markSynced(
                    recordType: .person, recordName: change.recordName, sentModifiedAt: change.modifiedAt, systemFields: nil
                )
            }
        }
    }

    /// Groups you are in. A profile that stayed back until it had a name has no copies to follow yet.
    private func zonesOfMe(_ recordName: String, people: [String: PersonRecord]) throws -> [String] {
        guard let person = people[recordName], person.kind == .me, metadata.zonesHoldingCopy(of: recordName).isEmpty else { return [] }
        return try tracker.context.fetch(FetchDescriptor<GroupRecord>())
            .filter { $0.deletedAt == nil && $0.memberIDs.contains(person.id) }
            .compactMap(\.zoneName)
            .filter { !metadata.isDetached(zoneName: $0) }
    }

    private func forgetCopies(of recordName: String, onlyIf condition: Bool) {
        guard condition else { return }
        updateMetadata { metadata in
            for zone in metadata.zonesHoldingCopy(of: recordName) {
                metadata.setCopy(nil, zoneName: zone, recordName: recordName)
            }
        }
    }

    /// The record to upload for a pending change, or nil when there is nothing to send any more.
    func outgoingRecord(for id: CKRecord.ID) throws -> CKRecord? {
        guard let type = try resolveType(of: id),
              let model = try type.modelType.find(recordName: id.recordName, in: tracker.context) else {
            return nil
        }
        let zone = id.zoneID.zoneName
        if type == .person {
            guard model.deletedAt == nil, (model as? PersonRecord)?.hasNameToShare != false else { return nil }
            let queued = metadata.personQueue.contains(PersonCopyKey(zoneName: zone, recordName: id.recordName))
            guard queued || metadata.copyNeedsUpload(zoneName: zone, recordName: id.recordName, modifiedAt: model.modifiedAt) else {
                return nil
            }
            let systemFields = metadata.copy(zoneName: zone, recordName: id.recordName)?.systemFields
            return RecordMapper.record(for: model.syncPayload, in: id.zoneID, systemFields: systemFields)
        }
        guard model.isDirty, model.pendingOperation == .save else { return nil }
        return RecordMapper.record(for: model.syncPayload, in: id.zoneID, systemFields: model.systemFields)
    }

    func resolveType(of id: CKRecord.ID) throws -> SyncRecordType? {
        if let known = knownTypes[id] { return known }
        for type in SyncRecordType.allCases {
            if try type.modelType.find(recordName: id.recordName, in: tracker.context) != nil {
                knownTypes[id] = type
                return type
            }
        }
        return nil
    }
}

extension PersonRecord {
    /// False for a profile still called "You", which would show to friends as a person named "You"
    /// and could replace the name this person chose on another device.
    fileprivate var hasNameToShare: Bool {
        kind != .me || name != String(localized: "You")
    }
}
