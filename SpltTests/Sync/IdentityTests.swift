import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Cloud identity")
struct CloudIdentityTests {
    @Test func theSameUserAlwaysGetsTheSamePerson() {
        let first = CloudIdentity.personID(forUserRecordName: "_abc123")
        let second = CloudIdentity.personID(forUserRecordName: "_abc123")
        #expect(first == second)
        #expect(first != CloudIdentity.personID(forUserRecordName: "_abc124"))
    }

    @Test func idsLookLikeNormalUUIDs() {
        let id = CloudIdentity.personID(forUserRecordName: "_abc123").rawValue.uuidString
        #expect(id.count == 36)
        let characters = Array(id)
        #expect(characters[14] == "5")
        #expect("89AB".contains(characters[19]))
    }

    @Test func theIdentityIsFixedForAKnownName() {
        #expect(CloudIdentity.personID(forUserRecordName: "_known").rawValue.uuidString == CloudIdentity.personID(forUserRecordName: "_known").rawValue.uuidString)
    }

    @Test func aDeviceWithoutAProfileRecognizesItselfWhenItsPersonArrives() throws {
        let device = try SyncDevice()
        let mine = CloudIdentity.personID(forUserRecordName: "_me")
        var fields = SyncFields()
        fields.set("name", "Sam")
        fields.set("kind", PersonKind.friend.rawValue)
        try device.tracker.applyRemote(SyncPayload(
            recordType: .person, recordName: mine.description, modifiedAt: device.clock.start, fields: fields
        ))
        #expect(try IdentityAdopter(tracker: device.tracker).adopt(userRecordName: "_me") == .adopted(mine))
        #expect(try device.services.people.me()?.id == mine)
        #expect(try device.services.people.me()?.name == "Sam")
        #expect(try device.services.people.friends().isEmpty)
        #expect(try device.tracker.pendingChanges().isEmpty)
    }

    @Test func adoptingRewritesTheProfileAndEveryReference() throws {
        let populated = try PopulatedDevice()
        let expense = try populated.addExpense()
        let old = populated.me.id
        let tracker = populated.device.tracker
        let result = try IdentityAdopter(tracker: tracker).adopt(userRecordName: "_alice")
        let new = CloudIdentity.personID(forUserRecordName: "_alice")
        #expect(result == .adopted(new))

        let services = populated.device.services
        let me = try #require(try services.people.me())
        #expect(me.id == new)
        #expect(me.name == "Me")
        #expect(me.claimedByCloudUserID == "_alice")
        #expect(try services.people.person(id: old) == nil)

        let group = try #require(try services.groups.group(id: populated.group.id))
        #expect(group.memberIDs.contains(new))
        #expect(!group.memberIDs.contains(old))
        let stored = try #require(try services.expenses.expense(id: expense.id))
        #expect(stored.payers.keys.contains(new))
        #expect(!stored.payers.keys.contains(old))
        #expect(stored.participants.contains(new))
        #expect(!stored.participants.contains(old))
        let balances = try services.groups.balances(for: group.id)
        #expect(!balances.netBalances.isEmpty)
    }

    @Test func adoptingIsRepeatableAndLeavesOtherDevicesWithTheSameIdentity() throws {
        let first = try PopulatedDevice()
        let second = try PopulatedDevice()
        let adopter1 = IdentityAdopter(tracker: first.device.tracker)
        let adopter2 = IdentityAdopter(tracker: second.device.tracker)
        let id = CloudIdentity.personID(forUserRecordName: "_alice")
        #expect(try adopter1.adopt(userRecordName: "_alice") == .adopted(id))
        #expect(try adopter1.adopt(userRecordName: "_alice") == .alreadyUsing(id))
        #expect(try adopter2.adopt(userRecordName: "_alice") == .adopted(id))
        #expect(try first.device.services.people.me()?.id == second.device.services.people.me()?.id)
    }

    @Test func noProfileMeansNothingToAdopt() throws {
        let device = try SyncDevice()
        #expect(try IdentityAdopter(tracker: device.tracker).adopt(userRecordName: "_alice") == .noProfile)
    }

    @Test func anExistingRecordForTheIdentityBecomesTheProfile() throws {
        let populated = try PopulatedDevice()
        let target = CloudIdentity.personID(forUserRecordName: "_alice")
        try populated.device.services.people.add(Person(
            id: target, name: "Alice from cloud", kind: .friend, createdAt: populated.device.clock.start
        ))
        let result = try IdentityAdopter(tracker: populated.device.tracker).adopt(userRecordName: "_alice")
        #expect(result == .adopted(target))
        let me = try #require(try populated.device.services.people.me())
        #expect(me.id == target)
        #expect(me.name == "Alice from cloud")
        #expect(try populated.device.services.people.friends().filter { $0.id == target }.isEmpty)
    }

    @Test func theOldProfileIsDeletedOnTheServerOnlyIfItWasUploaded() throws {
        let populated = try PopulatedDevice()
        let cloud = FakeCloud()
        try cloud.upload(from: populated.device)
        try IdentityAdopter(tracker: populated.device.tracker).adopt(userRecordName: "_alice")
        let plan = try populated.device.adapter.collectOutgoing()
        #expect(plan.deletes.contains { $0.recordName == populated.me.id.description })
    }

    @Test func aProfileWithTheSameFriendInTheSameExpenseIsLeftAlone() throws {
        let populated = try PopulatedDevice()
        let target = CloudIdentity.personID(forUserRecordName: "_alice")
        try populated.device.services.people.add(Person(
            id: target, name: "Alice", kind: .friend, createdAt: populated.device.clock.start
        ))
        let tangled = Expense(
            groupID: populated.group.id, title: "Both", total: usdAmount(1000), date: populated.device.clock.start,
            paidBy: populated.me.id, split: .equal(participants: [populated.me.id, target])
        )
        try populated.device.services.groups.addMember(target, to: populated.group.id)
        try populated.device.services.expenses.add(tangled)
        let result = try IdentityAdopter(tracker: populated.device.tracker).adopt(userRecordName: "_alice")
        #expect(result == .blocked(records: 1))
        #expect(try populated.device.services.people.me()?.id == populated.me.id)
    }
}

@MainActor
@Suite("Placeholder claims")
struct PlaceholderClaimTests {
    private struct Setup {
        let populated: PopulatedDevice
        let hana: Person
        let casey: Person
    }

    private func setup() throws -> Setup {
        let populated = try PopulatedDevice()
        let created = populated.device.clock.start
        let hana = Person(name: "Hana", contactHint: "hana@example.com", kind: .placeholder, avatarSeed: 7, createdAt: created)
        let casey = Person(
            id: CloudIdentity.personID(forUserRecordName: "_casey"), name: "Casey", kind: .friend,
            claimedByCloudUserID: "_casey", createdAt: created
        )
        try populated.device.services.people.add(hana)
        try populated.device.services.people.add(casey)
        try populated.device.services.groups.addMember(hana.id, to: populated.group.id)
        return Setup(populated: populated, hana: hana, casey: casey)
    }

    @Test func claimingMovesEveryReferenceAndRemovesThePlaceholder() throws {
        let setup = try setup()
        let services = setup.populated.device.services
        let dinner = Expense(
            groupID: setup.populated.group.id, title: "Dinner", total: usdAmount(3000),
            date: setup.populated.device.clock.start, paidBy: setup.hana.id,
            split: .equal(participants: [setup.populated.me.id, setup.hana.id])
        )
        try services.expenses.add(dinner)
        try services.groups.addMember(setup.casey.id, to: setup.populated.group.id)
        let count = try PlaceholderClaimer(tracker: setup.populated.device.tracker)
            .claim(placeholder: setup.hana.id, by: setup.casey.id)
        #expect(count >= 2)

        let stored = try #require(try services.expenses.expense(id: dinner.id))
        #expect(stored.payers.keys.contains(setup.casey.id))
        #expect(!stored.participants.contains(setup.hana.id))
        let group = try #require(try services.groups.group(id: setup.populated.group.id))
        #expect(!group.memberIDs.contains(setup.hana.id))
        #expect(group.memberIDs.filter { $0 == setup.casey.id }.count == 1)
        #expect(try services.people.person(id: setup.hana.id) == nil)
        let casey = try #require(try services.people.person(id: setup.casey.id))
        #expect(casey.contactHint == "hana@example.com")
    }

    @Test func claimedChangesAreMarkedForUpload() throws {
        let setup = try setup()
        let cloud = FakeCloud()
        try cloud.upload(from: setup.populated.device)
        try PlaceholderClaimer(tracker: setup.populated.device.tracker).claim(placeholder: setup.hana.id, by: setup.casey.id)
        let pending = try setup.populated.device.tracker.pendingChanges()
        #expect(pending.contains { $0.recordType == .group })
        #expect(pending.contains { $0.recordType == .person && $0.operation == .delete })
    }

    @Test func onlyPlaceholdersCanBeClaimed() throws {
        let setup = try setup()
        let claimer = PlaceholderClaimer(tracker: setup.populated.device.tracker)
        #expect(throws: ClaimError.notAPlaceholder) {
            try claimer.claim(placeholder: setup.populated.sam.id, by: setup.casey.id)
        }
        #expect(throws: ClaimError.unknownPerson) {
            try claimer.claim(placeholder: PersonID(), by: setup.casey.id)
        }
    }

    @Test func aPlaceholderAndClaimerInTheSameExpenseCannotBeMergedAutomatically() throws {
        let setup = try setup()
        let services = setup.populated.device.services
        try services.groups.addMember(setup.casey.id, to: setup.populated.group.id)
        let both = Expense(
            groupID: setup.populated.group.id, title: "Both", total: usdAmount(1000),
            date: setup.populated.device.clock.start, paidBy: setup.populated.me.id,
            split: .equal(participants: [setup.hana.id, setup.casey.id])
        )
        try services.expenses.add(both)
        #expect(throws: ClaimError.bothInSameRecord(1)) {
            try PlaceholderClaimer(tracker: setup.populated.device.tracker)
                .claim(placeholder: setup.hana.id, by: setup.casey.id)
        }
        #expect(try services.people.person(id: setup.hana.id) != nil)
    }
}

@MainActor
@Suite("Participants")
struct ParticipantImporterTests {
    private func snapshot(_ name: String, display: String?, hints: [String] = [], joined: Bool = true, current: Bool = false) -> ParticipantSnapshot {
        ParticipantSnapshot(userRecordName: name, displayName: display, contactHints: hints, isCurrentUser: current, hasJoined: joined)
    }

    @Test func joinedParticipantsBecomePeopleWithADerivedID() throws {
        let populated = try PopulatedDevice()
        let importer = ParticipantImporter(services: populated.device.services)
        try importer.importPeople(
            from: [snapshot("_casey", display: "Casey Lee"), snapshot("_pending", display: "Nope", joined: false)],
            myUserRecordName: "_me"
        )
        let id = CloudIdentity.personID(forUserRecordName: "_casey")
        let person = try #require(try populated.device.services.people.person(id: id))
        #expect(person.name == "Casey Lee")
        #expect(person.claimedByCloudUserID == "_casey")
        #expect(try populated.device.services.people.person(id: CloudIdentity.personID(forUserRecordName: "_pending")) == nil)
    }

    @Test func importingTwiceDoesNotDuplicateAndSkipsYou() throws {
        let populated = try PopulatedDevice()
        let importer = ParticipantImporter(services: populated.device.services)
        let before = try populated.device.services.people.allPeople().count
        let list = [snapshot("_casey", display: "Casey"), snapshot("_me", display: "Me", current: true)]
        try importer.importPeople(from: list, myUserRecordName: "_me")
        try importer.importPeople(from: list, myUserRecordName: "_me")
        #expect(try populated.device.services.people.allPeople().count == before + 1)
    }

    @Test func nameFallsBackWhenTheParticipantIsNotDiscoverable() throws {
        let populated = try PopulatedDevice()
        try ParticipantImporter(services: populated.device.services)
            .importPeople(from: [snapshot("_quiet", display: nil)], myUserRecordName: "_me")
        let person = try populated.device.services.people.person(id: CloudIdentity.personID(forUserRecordName: "_quiet"))
        #expect(person?.name == "Friend")
    }

    @Test func youAreAddedToTheGroupOnlyOnce() throws {
        let populated = try PopulatedDevice()
        let importer = ParticipantImporter(services: populated.device.services)
        let mine = CloudIdentity.personID(forUserRecordName: "_me")
        try populated.device.services.people.add(Person(id: mine, name: "Me again", createdAt: populated.device.clock.start))
        try importer.ensureMembership(ofMe: "_me", inZone: populated.zone)
        try importer.ensureMembership(ofMe: "_me", inZone: populated.zone)
        let group = try #require(try populated.device.services.groups.group(id: populated.group.id))
        #expect(group.memberIDs.filter { $0 == mine }.count == 1)
    }

    @Test func zonesThatAreNotGroupsAreIgnored() throws {
        let populated = try PopulatedDevice()
        try ParticipantImporter(services: populated.device.services).ensureMembership(ofMe: "_me", inZone: "not-a-uuid")
        try ParticipantImporter(services: populated.device.services).ensureMembership(ofMe: "_me", inZone: UUID().uuidString)
    }
}
