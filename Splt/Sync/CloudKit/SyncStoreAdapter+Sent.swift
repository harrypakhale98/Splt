import CloudKit
import Foundation

/// What to do after one upload failed.
struct SaveFailureOutcome: Equatable {
    var failure: SyncFailure
    /// The change should be queued again, for example after a conflict the local version won.
    var requeue = false
    var recreateZone: CKRecordZone.ID?
    /// A zone the server once confirmed is now missing. A fetch has to tell why before it may come back:
    /// another device may have deleted the group.
    var askServerAbout: CKRecordZone.ID?
    /// A shared zone that is gone, treated like a zone the owner deleted.
    var goneZone: CKRecordZone.ID?
    /// A zone the person deleted in their iCloud storage settings. It is not made again.
    var purgedZone: CKRecordZone.ID?
}

extension SyncStoreAdapter {
    /// Records the server accepted and records it deleted. Returns the accepted records that no longer
    /// exist here: they were deleted during their first upload, so the server must delete them too.
    @discardableResult
    func didSend(saved: [CKRecord], deleted: [CKRecord.ID]) throws -> [CKRecord.ID] {
        var copies: [(PersonCopyKey, PersonCopy)] = []
        var orphans: [CKRecord.ID] = []
        var attachmentSlots: [String: [String: String?]] = [:]
        for record in saved {
            guard let type = SyncRecordType(rawValue: record.recordType) else { continue }
            guard let model = try type.modelType.find(recordName: record.recordID.recordName, in: tracker.context) else {
                orphans.append(record.recordID)
                continue
            }
            let sentSlots = sentAttachmentSlots(record, type: type, wasNew: model.systemFields == nil)
            if !sentSlots.isEmpty {
                attachmentSlots[record.recordID.zoneID.zoneName, default: [:]].merge(sentSlots) { $1 }
            }
            let sentAt = (record[RecordSchema.modifiedAtKey] as? Date) ?? .distantPast
            let systemFields = RecordMapper.encodeSystemFields(record)
            if type == .person {
                let key = PersonCopyKey(zoneName: record.recordID.zoneID.zoneName, recordName: record.recordID.recordName)
                copies.append((key, PersonCopy(systemFields: systemFields, sentModifiedAt: sentAt)))
            } else {
                try tracker.markSynced(
                    recordType: type, recordName: record.recordID.recordName,
                    sentModifiedAt: sentAt, systemFields: systemFields
                )
            }
        }
        if !copies.isEmpty {
            // an uploaded person is marked with system fields so a later delete is not dropped as "never synced"
            for (key, copy) in copies {
                if let model = try PersonRecord.find(recordName: key.recordName, in: tracker.context), model.systemFields == nil {
                    model.systemFields = copy.systemFields
                }
            }
            try tracker.save()
            updateMetadata { metadata in
                for (key, copy) in copies {
                    metadata.setCopy(copy, zoneName: key.zoneName, recordName: key.recordName)
                    metadata.personQueue.remove(key)
                }
            }
        }
        if !attachmentSlots.isEmpty {
            updateMetadata { metadata in
                for (zone, slots) in attachmentSlots {
                    metadata.setAttachments(slots, zoneName: zone)
                }
            }
        }
        for id in deleted {
            try didDelete(id)
        }
        return orphans
    }

    /// What the server holds in each asset field of a record it accepted, worked out the same way
    /// `AttachmentSync.attach` built the upload, before the record is marked as synced.
    private func sentAttachmentSlots(_ record: CKRecord, type: SyncRecordType, wasNew: Bool) -> [String: String?] {
        var slots: [String: String?] = [:]
        let zone = record.recordID.zoneID.zoneName
        for attachment in RecordSchema.attachments(for: type) {
            let slot = AttachmentSync.slot(recordName: record.recordID.recordName, assetKey: attachment.assetKey)
            let held = wasNew ? nil : metadata.attachmentOnServer(zoneName: zone, slot: slot)
            slots[slot] = .some(attachments.heldAfterSave(
                name: record[attachment.nameKey] as? String, held: held, folder: attachment.folder
            ))
        }
        return slots
    }

    private func didDelete(_ id: CKRecord.ID) throws {
        let name = id.recordName
        let isPersonCopy = metadata.copy(zoneName: id.zoneID.zoneName, recordName: name) != nil
        if isPersonCopy {
            updateMetadata { $0.setCopy(nil, zoneName: id.zoneID.zoneName, recordName: name) }
        }
        guard let type = try resolveType(of: id),
              let model = try type.modelType.find(recordName: name, in: tracker.context),
              model.pendingOperation == .delete else { return }
        if type == .person {
            guard metadata.privateZonesHoldingCopy(of: name).isEmpty else { return }
            updateMetadata { metadata in
                for zone in metadata.zonesHoldingCopy(of: name) {
                    metadata.setCopy(nil, zoneName: zone, recordName: name)
                }
            }
        }
        try tracker.markSynced(recordType: type, recordName: name, sentModifiedAt: model.modifiedAt, systemFields: nil)
    }

    /// Decides what a failed upload needs. Conflicts are merged with the data layer's policy.
    func saveFailed(record: CKRecord, error: CKError) throws -> SaveFailureOutcome {
        let failure = SyncFailure(error)
        var outcome = SaveFailureOutcome(failure: failure)
        switch failure {
        case .conflict:
            if let server = error.serverRecord {
                let report = try applyFetched(modifications: [server], deletions: [])
                outcome.requeue = report.requeue.contains(record.recordID)
                if server.recordType != record.recordType {
                    // a record of another type holds this name, so nothing sent from here can replace it
                    outcome.requeue = false
                    outcome.failure = .other(SyncFailure.genericMessage)
                } else if report.refused.contains(server.recordID) {
                    // the server holds a copy this device does not believe. With that copy's change tag the
                    // local version replaces it on the next send, instead of failing the same way for ever.
                    outcome.requeue = try adoptSystemFields(of: server)
                }
            } else {
                outcome.requeue = true
            }
        case .itemMissing:
            try forgetSystemFields(of: record.recordID)
            outcome.requeue = true
        case .zoneMissing:
            let zone = record.recordID.zoneID
            if error.code == .userDeletedZone, zone.scope == .privateDatabase {
                outcome.purgedZone = zone
            } else if zone.scope == .privateDatabase, metadata.isKnown(zoneName: zone.zoneName) {
                outcome.askServerAbout = zone
            } else if zone.scope == .privateDatabase {
                // A group deleted here took its zone with it, and one kept as a local copy has no zone on
                // purpose. A save that was still on its way must not bring either zone back with one
                // stray record in it.
                if !metadata.isDetached(zoneName: zone.zoneName),
                   let group = try GroupRecord.find(recordName: zone.zoneName, in: tracker.context), group.deletedAt == nil {
                    outcome.recreateZone = zone
                    outcome.requeue = true
                }
            } else {
                outcome.goneZone = zone
            }
        default:
            break
        }
        return outcome
    }

    /// A delete that finds nothing to delete, or no zone to delete it from, has done its job.
    func deleteFailed(id: CKRecord.ID, error: CKError) throws -> SyncFailure {
        let failure = SyncFailure(error)
        if failure == .itemMissing || failure == .zoneMissing {
            try didSend(saved: [], deleted: [id])
        }
        return failure
    }

    /// Takes the change tag of a server record without taking anything it says. Returns true when the
    /// local version is still waiting to be sent.
    private func adoptSystemFields(of server: CKRecord) throws -> Bool {
        let id = server.recordID
        let zone = id.zoneID.zoneName
        guard let type = try resolveType(of: id),
              let model = try type.modelType.find(recordName: id.recordName, in: tracker.context) else { return false }
        let systemFields = RecordMapper.encodeSystemFields(server)
        if type == .person {
            updateMetadata { metadata in
                metadata.setCopy(PersonCopy(systemFields: systemFields, sentModifiedAt: .distantPast), zoneName: zone, recordName: id.recordName)
                metadata.personQueue.insert(PersonCopyKey(zoneName: zone, recordName: id.recordName))
            }
            return true
        }
        guard model.isDirty, model.pendingOperation == .save else { return false }
        // the server copy may hold another photo now, so the next upload decides afresh
        let slots = RecordSchema.attachments(for: type).map {
            (AttachmentSync.slot(recordName: id.recordName, assetKey: $0.assetKey), String?.none)
        }
        updateMetadata { $0.setAttachments(Dictionary(uniqueKeysWithValues: slots), zoneName: zone) }
        model.systemFields = systemFields
        try tracker.save()
        return true
    }

    private func forgetSystemFields(of id: CKRecord.ID) throws {
        let zone = id.zoneID.zoneName
        if metadata.copy(zoneName: zone, recordName: id.recordName) != nil {
            updateMetadata { metadata in
                metadata.setCopy(PersonCopy(systemFields: nil, sentModifiedAt: .distantPast), zoneName: zone, recordName: id.recordName)
                metadata.personQueue.insert(PersonCopyKey(zoneName: zone, recordName: id.recordName))
            }
            return
        }
        guard let type = try resolveType(of: id),
              let model = try type.modelType.find(recordName: id.recordName, in: tracker.context) else { return }
        model.systemFields = nil
        try tracker.save()
    }
}
