import CloudKit
import Foundation

enum DatabaseScope: String, Codable, Hashable, Sendable, CaseIterable {
    /// Groups you created.
    case privateDatabase
    /// Groups other people shared with you.
    case sharedDatabase
}

struct ZoneInfo: Codable, Hashable, Sendable {
    var ownerName: String
    var scope: DatabaseScope
}

/// A person is one local record but uploads as a copy into every group zone that mentions them.
/// This is what the last upload of one copy looked like.
struct PersonCopy: Codable, Hashable, Sendable {
    var systemFields: Data?
    var sentModifiedAt: Date
}

struct PersonCopyKey: Codable, Hashable, Sendable {
    var zoneName: String
    var recordName: String
}

/// What sync remembers between launches that the data store does not hold.
struct SyncMetadata: Codable, Equatable, Sendable {
    /// The iCloud user the local sync state belongs to.
    var userRecordName: String?
    var zones: [String: ZoneInfo] = [:]
    var personCopies: [String: [String: PersonCopy]] = [:]
    /// Person copies that still have to be uploaded.
    var personQueue: Set<PersonCopyKey> = []

    func zoneID(forZoneName name: String) -> CKRecordZone.ID {
        let owner = zones[name]?.ownerName ?? CKCurrentUserDefaultName
        return CKRecordZone.ID(zoneName: name, ownerName: owner)
    }

    func scope(forZoneName name: String) -> DatabaseScope {
        zones[name]?.scope ?? .privateDatabase
    }

    func isKnown(zoneName: String) -> Bool {
        zones[zoneName] != nil
    }

    func copy(zoneName: String, recordName: String) -> PersonCopy? {
        personCopies[zoneName]?[recordName]
    }

    mutating func setCopy(_ copy: PersonCopy?, zoneName: String, recordName: String) {
        personCopies[zoneName, default: [:]][recordName] = copy
        if personCopies[zoneName]?.isEmpty == true {
            personCopies[zoneName] = nil
        }
    }

    func zonesHoldingCopy(of recordName: String) -> [String] {
        personCopies.filter { $0.value[recordName] != nil }.map(\.key).sorted()
    }

    /// Copies in zones of your own private database. Deleting a person only removes these, never a
    /// copy in someone else's shared group.
    func privateZonesHoldingCopy(of recordName: String) -> [String] {
        zonesHoldingCopy(of: recordName).filter { scope(forZoneName: $0) == .privateDatabase }
    }

    mutating func forget(zoneName: String) {
        zones[zoneName] = nil
        personCopies[zoneName] = nil
        personQueue = personQueue.filter { $0.zoneName != zoneName }
    }
}
