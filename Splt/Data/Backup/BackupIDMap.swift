import CryptoKit
import Foundation

/// The new id of every id in a backup, for a restore.
///
/// A restored group becomes a new group in your own iCloud, so nothing in it may keep its old id:
/// copies of the same group can still live in someone else's iCloud. New ids are worked out from
/// the old id and this device's "me", rather than drawn at random, so restoring the same backup
/// twice gives the same ids and the second time finds the groups already here instead of adding
/// them again. Ids the app works out from other ids, such as a person's claim on an expense, are
/// worked out again from the new ids by `BackupRestorer`, and set here as overrides.
struct BackupIDMap {
    /// Mixed into every new id, so another person restoring the same backup gets other ids.
    let salt: UUID
    private(set) var overrides: [UUID: UUID] = [:]

    init(salt: UUID) {
        self.salt = salt
    }

    subscript(_ old: UUID) -> UUID {
        overrides[old] ?? Self.derived(old, salt: salt)
    }

    mutating func set(_ old: UUID, to new: UUID) {
        overrides[old] = new
    }

    /// The fields with every id replaced: an id field (one whose name ends in "ID") when it holds
    /// exactly one id, and every id written anywhere in a blob such as a split or an event. Other
    /// text, such as a note, is left alone even when it happens to hold an id.
    func remapped(_ fields: SyncFields) -> SyncFields {
        var result = fields
        for (key, value) in fields.values {
            switch value {
            case .string(let text) where key.hasSuffix("ID"):
                if let id = UUID(uuidString: text) { result.set(key, self[id].uuidString) }
            case .data(let data):
                result.set(key, UUIDScanner.replacingUUIDs(in: data) { self[$0] })
            default:
                continue
            }
        }
        return result
    }

    /// The name a restored photo is saved under. It never comes from the file.
    func photoName(for folder: BackupPhoto.Folder, original: String) -> String {
        Self.hashed("splt.restore.photo.v1:\(salt.uuidString):\(folder.rawValue):\(original)").uuidString + ".jpg"
    }

    static func derived(_ old: UUID, salt: UUID) -> UUID {
        hashed("splt.restore.v1:\(salt.uuidString):\(old.uuidString)")
    }

    private static func hashed(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // name based
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}
