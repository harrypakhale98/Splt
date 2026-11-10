import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Person repository")
struct PersonRepositoryTests {
    @Test func ensureMeCreatesTheProfileOnce() throws {
        let services = try DataServices.inMemory()
        let first = try services.people.ensureMe(name: "Hardik")
        let second = try services.people.ensureMe(name: "Someone else")
        #expect(first == second)
        #expect(first.isMe)
        #expect(try services.people.me()?.name == "Hardik")
    }

    @Test func friendsExcludeMeAndSortByName() throws {
        let services = try DataServices.inMemory()
        try services.people.ensureMe(name: "Me")
        for name in ["zoe", "Alex", "maya"] {
            try services.people.add(Person(name: name))
        }
        #expect(try services.people.friends().map(\.name) == ["Alex", "maya", "zoe"])
        #expect(try services.people.allPeople().count == 4)
    }

    @Test func peopleComeBackInTheRequestedOrder() throws {
        let services = try DataServices.inMemory()
        let a = Person(name: "A")
        let b = Person(name: "B")
        try services.people.add(a)
        try services.people.add(b)
        let missing = PersonID()
        #expect(try services.people.people(ids: [b.id, missing, a.id]).map(\.name) == ["B", "A"])
    }

    @Test func updateChangesTheStoredPerson() throws {
        let services = try DataServices.inMemory()
        var person = Person(name: "Sam", avatarSeed: 4)
        try services.people.add(person)
        person.name = "Samuel"
        person.contactHint = "sam@example.com"
        try services.people.update(person)
        #expect(try services.people.person(id: person.id) == person)
    }

    @Test func updatingAnUnknownPersonThrows() throws {
        let services = try DataServices.inMemory()
        #expect(throws: DataError.self) { try services.people.update(Person(name: "Ghost")) }
    }

    @Test func claimingAPlaceholderMakesItAFriendWithACloudUser() throws {
        let services = try DataServices.inMemory()
        let placeholder = Person(name: "Hana", kind: .placeholder)
        try services.people.add(placeholder)
        try services.people.claim(placeholder.id, cloudUserID: "_user1")
        let claimed = try #require(try services.people.person(id: placeholder.id))
        #expect(claimed.kind == .friend)
        #expect(claimed.claimedByCloudUserID == "_user1")
    }

    @Test func editsAreTrackedForSync() throws {
        let services = try DataServices.inMemory()
        try services.people.add(Person(name: "Sam"))
        let pending = try services.makeChangeTracker().pendingChanges()
        #expect(pending.map(\.recordType) == [.person])
    }
}
