import CloudKit
import Foundation

/// Carries photo files next to records: a receipt with its expense, a cover photo with its group.
///
/// The record names the photo, and the photo travels in an asset field of the same record, so the
/// two always arrive together. A photo is uploaded only when the server does not already hold that
/// photo in that record, which `SyncMetadata.attachmentsOnServer` remembers, so editing an expense
/// does not send its receipt again.
struct AttachmentSync: Sendable {
    let store: @Sendable (Attachment.Folder) -> PhotoStore

    static let live = AttachmentSync { folder in
        switch folder {
        case .receipts: .receipts
        case .covers: .covers
        }
    }

    /// The key under which `SyncMetadata` remembers the photo in one asset field of one record.
    static func slot(recordName: String, assetKey: String) -> String {
        recordName + "/" + assetKey
    }

    /// Puts the photos the server lacks into an outgoing record, and empties an asset field whose
    /// photo the record no longer names. `onServer` gives the photo the server holds in a slot.
    func attach(
        to record: CKRecord, type: SyncRecordType, fields: SyncFields, onServer: (String) -> String?
    ) {
        for attachment in RecordSchema.attachments(for: type) {
            let slot = Self.slot(recordName: record.recordID.recordName, assetKey: attachment.assetKey)
            let name = fields.string(attachment.nameKey)
            let held = onServer(slot)
            guard let name, name != held else {
                if name == nil { record[attachment.assetKey] = nil }
                continue
            }
            let photos = store(attachment.folder)
            // a photo this device does not have must not stay paired with another photo's name
            record[attachment.assetKey] = photos.exists(name) ? CKAsset(fileURL: photos.url(for: name)) : nil
        }
    }

    /// The photo the server holds in a slot once a record built by `attach` is saved.
    func heldAfterSave(name: String?, held: String?, folder: Attachment.Folder) -> String? {
        guard let name else { return nil }
        return name == held || store(folder).exists(name) ? name : nil
    }

    /// What the server holds in each asset field of a record it confirmed or sent: the photo name per
    /// slot, or nil for an empty field. Photos that came with a fetched record are kept on the device.
    ///
    /// The file is only there while the engine's callback runs, so it is taken now. Its thumbnail is made
    /// afterwards in a detached task, which keeps the decoding off the main actor and out of the callback.
    func received(_ record: CKRecord, type: SyncRecordType, keepFiles: Bool) -> [String: String?] {
        var slots: [String: String?] = [:]
        var kept: [(PhotoStore, String)] = []
        for attachment in RecordSchema.attachments(for: type) {
            let slot = Self.slot(recordName: record.recordID.recordName, assetKey: attachment.assetKey)
            guard let asset = record[attachment.assetKey] as? CKAsset,
                  let name = record[attachment.nameKey] as? String else {
                slots[slot] = .some(nil)
                continue
            }
            let photos = store(attachment.folder)
            if keepFiles, let url = asset.fileURL, photos.adopt(fileAt: url, named: name) {
                kept.append((photos, name))
            }
            slots[slot] = .some(name)
        }
        if !kept.isEmpty {
            let thumbnails = kept
            Task.detached(priority: .utility) {
                for (photos, name) in thumbnails { photos.makeThumbnail(for: name) }
            }
        }
        return slots
    }
}
