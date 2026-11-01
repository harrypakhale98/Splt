import CryptoKit
import Foundation
import SpltCore

/// Turns an iCloud user into a person id that is the same on every device and for every group member.
enum CloudIdentity {
    /// A stable id for the iCloud user record name. Hashing keeps the id well formed and the same
    /// everywhere without storing a lookup table.
    static func personID(forUserRecordName name: String) -> PersonID {
        var bytes = Array(SHA256.hash(data: Data("splt.person.v1:\(name)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let uuid = bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        return PersonID(rawValue: uuid)
    }
}
