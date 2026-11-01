import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Merging placeholders")
struct PlaceholderMergeTests {
    private func scene() throws -> (fixture: Fixture, placeholder: Person) {
        let fixture = try Fixture()
        let placeholder = Person(name: "Sam P", kind: .placeholder)
        try fixture.services.people.add(placeholder)
        try fixture.services.groups.addMember(placeholder.id, to: fixture.group.id)
        return (fixture, placeholder)
    }

    @Test func movesSharedExpensesToTheRealPerson() throws {
        let (fixture, placeholder) = try scene()
        let trip = SplitGroup(name: "Trip", currencyCode: "USD", memberIDs: [fixture.me.id, placeholder.id])
        try fixture.services.groups.create(trip)
        try fixture.services.expenses.add(Expense(
            groupID: trip.id, title: "Museum", total: usdAmount(2000), date: fixture.clock.start,
            paidBy: fixture.me.id, split: .equal(participants: [fixture.me.id, placeholder.id])
        ))

        let model = MergeFriendModel(placeholder: placeholder, services: fixture.services, merger: LivePlaceholderMerger(services: fixture.services))
        model.merge(into: fixture.sam)

        #expect(model.didMerge == fixture.sam)
        #expect(model.errorMessage == nil)
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.total == [usdAmount(1000)])
        #expect(try fixture.services.people.person(id: placeholder.id) == nil)
        let members = try #require(try fixture.services.groups.group(id: trip.id)).memberIDs
        #expect(members.contains(fixture.sam.id))
        #expect(!members.contains(placeholder.id))
    }

    @Test func refusesWhenBothAreInTheSameExpense() throws {
        let (fixture, placeholder) = try scene()
        try fixture.addExpense("Dinner", cents: 4000, splitBetween: [fixture.me.id, fixture.sam.id, placeholder.id])

        let model = MergeFriendModel(placeholder: placeholder, services: fixture.services, merger: LivePlaceholderMerger(services: fixture.services))
        model.merge(into: fixture.sam)

        #expect(model.didMerge == nil)
        #expect(model.errorMessage == MergeError.sharedRecord(1).message)
        #expect(try fixture.services.people.person(id: placeholder.id) != nil)
    }

    @Test func onlyPlaceholdersCanBeMerged() throws {
        let fixture = try Fixture()
        let merger = LivePlaceholderMerger(services: fixture.services)
        #expect(throws: MergeError.notAPlaceholder) {
            try merger.merge(fixture.sam.id, into: fixture.priya.id)
        }
        #expect(throws: MergeError.unknownPerson) {
            try merger.merge(PersonID(), into: fixture.priya.id)
        }
    }

    @Test func suggestsLookAlikesFirst() throws {
        let (fixture, placeholder) = try scene()
        let model = MergeFriendModel(placeholder: placeholder, services: fixture.services, merger: LivePlaceholderMerger(services: fixture.services))
        #expect(model.suggestions.map(\.name) == ["Sam"])
        #expect(model.others.map(\.name) == ["Priya"])
    }
}
