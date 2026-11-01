import SpltCore

extension Person {
    init(_ record: PersonRecord) {
        self.init(
            id: record.personID, name: record.name, contactHint: record.contactHint, kind: record.kind,
            claimedByCloudUserID: record.claimedByCloudUserID, avatarSeed: record.avatarSeed,
            createdAt: record.createdAt
        )
    }
}

extension PersonRecord {
    convenience init(_ person: Person) {
        self.init(
            id: person.id.rawValue, name: person.name, contactHint: person.contactHint, kind: person.kind,
            claimedByCloudUserID: person.claimedByCloudUserID, avatarSeed: person.avatarSeed,
            createdAt: person.createdAt
        )
    }

    func update(from person: Person) {
        name = person.name
        contactHint = person.contactHint
        kind = person.kind
        claimedByCloudUserID = person.claimedByCloudUserID
        avatarSeed = person.avatarSeed
    }
}
