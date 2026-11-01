import Foundation
import SpltCore

/// A person as the rest of the app sees them.
struct Person: Hashable, Sendable, Codable, Identifiable {
    var id: PersonID
    var name: String
    var contactHint: String?
    var kind: PersonKind
    var claimedByCloudUserID: String?
    var avatarSeed: Int
    var createdAt: Date

    init(
        id: PersonID = PersonID(),
        name: String,
        contactHint: String? = nil,
        kind: PersonKind = .friend,
        claimedByCloudUserID: String? = nil,
        avatarSeed: Int = Int.random(in: 0..<10_000),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.contactHint = contactHint
        self.kind = kind
        self.claimedByCloudUserID = claimedByCloudUserID
        self.avatarSeed = avatarSeed
        self.createdAt = createdAt
    }

    var isMe: Bool { kind == .me }
    var isPlaceholder: Bool { kind == .placeholder }
}
