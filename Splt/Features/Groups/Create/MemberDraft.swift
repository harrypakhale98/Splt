import Foundation
import SpltCore

/// Someone about to join a group: a person already in the app, or a name that becomes a placeholder.
struct MemberDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var contactHint: String?
    /// Set when the person already exists, so no new placeholder is made.
    var existingID: PersonID?

    init(id: UUID = UUID(), name: String, contactHint: String? = nil, existingID: PersonID? = nil) {
        self.id = id
        self.name = name
        self.contactHint = contactHint
        self.existingID = existingID
    }

    init(person: Person) {
        self.init(name: person.name, contactHint: person.contactHint, existingID: person.id)
    }
}
