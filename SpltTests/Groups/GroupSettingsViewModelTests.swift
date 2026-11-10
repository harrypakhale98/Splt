import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Group settings")
struct GroupSettingsViewModelTests {
    private func makeModel(
        _ fixture: Fixture, groupID: GroupID? = nil, leftGroups: LeftGroupsStore = isolatedLeftGroups()
    ) -> GroupSettingsViewModel {
        let model = GroupSettingsViewModel(
            groupID: groupID ?? fixture.group.id, services: fixture.services, leftGroups: leftGroups,
            now: { utcDate(2026, 5, 20) }
        )
        model.locale = GroupsTestCalendar.english
        return model
    }

    // MARK: Editing

    @Test func loadsTheCurrentValues() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        #expect(model.name == "Flat")
        #expect(model.currencyCode == "USD")
        #expect(model.memberRows.count == 3)
        #expect(!model.isTrip)
        #expect(model.canSave)
    }

    @Test func savingChangesNameSymbolAndCurrency() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.name = "  Flat 4B "
        model.chooseSymbol("house.fill")
        model.currencyCode = "eur"
        try model.save()

        let saved = try #require(try fixture.services.groups.group(id: fixture.group.id))
        #expect(saved.name == "Flat 4B")
        #expect(saved.symbol == "house.fill")
        #expect(saved.currencyCode == "EUR")
        #expect(saved.memberIDs == fixture.group.memberIDs)
    }

    @Test func aBlankNameCannotBeSaved() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.name = "   "
        #expect(!model.canSave)
        try model.save()
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.name == "Flat")
    }

    private func tripFixture() throws -> (Fixture, SplitGroup) {
        let fixture = try Fixture()
        let trip = SplitGroup(
            name: "Lisbon", currencyCode: "EUR", kind: .trip, memberIDs: [fixture.me.id, fixture.sam.id],
            tripStart: utcDate(2026, 5, 8), tripEnd: utcDate(2026, 5, 14)
        )
        try fixture.services.groups.create(trip)
        return (fixture, trip)
    }

    @Test func tripDatesAndAPinnedRateAreSaved() throws {
        let (fixture, trip) = try tripFixture()
        let model = makeModel(fixture, groupID: trip.id)
        #expect(model.isTrip)
        #expect(model.tripStart == utcDate(2026, 5, 8))

        model.tripEnd = utcDate(2026, 5, 20)
        model.pinsRate = true
        model.rateCurrencyCode = "USD"
        model.rateText = "0.92"
        #expect(model.canSave)
        try model.save()

        let saved = try #require(try fixture.services.groups.group(id: trip.id))
        #expect(saved.tripEnd == utcDate(2026, 5, 20))
        #expect(saved.pinnedRate == PinnedRate(from: "USD", to: "EUR", rate: Decimal(string: "0.92")!))

        let reloaded = makeModel(fixture, groupID: trip.id)
        #expect(reloaded.pinsRate)
        #expect(reloaded.rateCurrencyCode == "USD")
        #expect(reloaded.rate == Decimal(string: "0.92"))

        reloaded.pinsRate = false
        try reloaded.save()
        #expect(try fixture.services.groups.group(id: trip.id)?.pinnedRate == nil)
    }

    @Test func aPinnedRateNeedsAValidRateAndAnotherCurrency() throws {
        let (fixture, trip) = try tripFixture()
        let model = makeModel(fixture, groupID: trip.id)
        model.pinsRate = true
        model.rateCurrencyCode = "USD"

        model.rateText = ""
        #expect(!model.canSave)
        model.rateText = "abc"
        #expect(!model.canSave)
        model.rateText = "0"
        #expect(!model.canSave)
        model.rateText = "1.1"
        #expect(model.canSave)
        model.rateCurrencyCode = "EUR"
        #expect(!model.canSave)
    }

    @Test func aTripCannotEndBeforeItStarts() throws {
        let (fixture, trip) = try tripFixture()
        let model = makeModel(fixture, groupID: trip.id)
        model.tripEnd = utcDate(2026, 5, 1)
        #expect(!model.canSave)
        model.tripStart = utcDate(2026, 5, 1)
        model.tripStartChanged()
        #expect(model.canSave)
    }

    @Test func rateTextFollowsTheLocale() {
        let german = Locale(identifier: "de_DE")
        #expect(RateInput.parse("1,08", locale: german) == Decimal(string: "1.08"))
        #expect(RateInput.parse("1.08", locale: GroupsTestCalendar.english) == Decimal(string: "1.08"))
        #expect(RateInput.parse(" 2 ", locale: GroupsTestCalendar.english) == 2)
        #expect(RateInput.parse("-1", locale: GroupsTestCalendar.english) == nil)
        #expect(RateInput.parse("x", locale: GroupsTestCalendar.english) == nil)
        #expect(RateInput.string(Decimal(string: "0.0065")!, locale: GroupsTestCalendar.english) == "0.0065")
    }

    // MARK: Members

    @Test func aMemberWhoIsOwedCannotBeRemoved() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, paidBy: fixture.sam)
        let model = makeModel(fixture)
        let row = try #require(model.memberRows.first { $0.person.id == fixture.sam.id })

        model.remove(row)
        let message = try #require(model.blockedMessage)
        #expect(message.contains("Sam"))
        #expect(message.contains("is owed $20.00"))
        #expect(model.memberRows.count == 3)
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.memberIDs.contains(fixture.sam.id) == true)
    }

    @Test func aMemberWhoOwesCannotBeRemovedEither() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, paidBy: fixture.me)
        let model = makeModel(fixture)
        let row = try #require(model.memberRows.first { $0.person.id == fixture.sam.id })
        model.remove(row)
        #expect(try #require(model.blockedMessage).contains("owes $10.00"))
    }

    @Test func aSettledMemberCanBeRemoved() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        let model = makeModel(fixture)
        let row = try #require(model.memberRows.first { $0.person.id == fixture.priya.id })

        model.remove(row)
        #expect(model.blockedMessage == nil)
        #expect(model.memberRows.map(\.person.id).contains(fixture.priya.id) == false)
        #expect(model.friendsToAdd.map(\.id) == [fixture.priya.id])
    }

    @Test func removalWorksOnceThePersonSettlesUp() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        try fixture.services.payments.settle(
            Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(1500)),
            in: fixture.group.id, date: utcDate(2026, 5, 1)
        )
        let model = makeModel(fixture)
        let row = try #require(model.memberRows.first { $0.person.id == fixture.sam.id })
        model.remove(row)
        #expect(model.blockedMessage == nil)
        #expect(!model.memberRows.contains { $0.person.id == fixture.sam.id })
    }

    @Test func youCannotRemoveYourself() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        let mine = try #require(model.myRow)
        model.remove(mine)
        #expect(model.memberRows.count == 3)
    }

    @Test func addingByNameMakesAPlaceholderMember() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.addMember(named: " Alex ", contactHint: "alex@example.com")
        let row = try #require(model.memberRows.first { $0.person.name == "Alex" })
        #expect(row.person.isPlaceholder)
        #expect(row.person.contactHint == "alex@example.com")
        #expect(model.memberRows.count == 4)

        model.addMember(named: "   ")
        #expect(model.memberRows.count == 4)
    }

    @Test func addingAFriendReusesThePerson() throws {
        let fixture = try Fixture()
        let outsider = Person(name: "Dee")
        try fixture.services.people.add(outsider)
        let model = makeModel(fixture)
        #expect(model.friendsToAdd.map(\.id) == [outsider.id])
        model.addMember(outsider)
        #expect(model.memberRows.map(\.person.id).contains(outsider.id))
        #expect(model.friendsToAdd.isEmpty)
    }

    // MARK: Leaving, archiving, deleting

    @Test func youCanLeaveWhenSettled() async throws {
        let fixture = try Fixture()
        let leftGroups = isolatedLeftGroups()
        let model = makeModel(fixture, leftGroups: leftGroups)
        #expect(model.leaveBlock == nil)
        let left = await model.leave(using: LocalGroupSharing())
        #expect(left)
        #expect(leftGroups.contains(fixture.group.id))
        let group = try #require(try fixture.services.groups.group(id: fixture.group.id))
        #expect(!group.memberIDs.contains(fixture.me.id))
    }

    @Test func youCannotLeaveWithABalance() async throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let leftGroups = isolatedLeftGroups()
        let model = makeModel(fixture, leftGroups: leftGroups)
        let block = try #require(model.leaveBlock)
        #expect(block.contains("You're owed $20.00"))
        #expect(await model.leave(using: LocalGroupSharing()) == false)
        #expect(model.blockedMessage == block)
        #expect(!leftGroups.contains(fixture.group.id))
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.memberIDs.contains(fixture.me.id) == true)
    }

    @Test func theOnlyMemberShouldDeleteInstead() throws {
        let fixture = try Fixture()
        let solo = SplitGroup(name: "Solo", currencyCode: "USD", memberIDs: [fixture.me.id])
        try fixture.services.groups.create(solo)
        let model = makeModel(fixture, groupID: solo.id)
        #expect(model.leaveBlock?.contains("only member") == true)
    }

    @Test func archiveAndRestoreToggle() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.toggleArchived()
        #expect(model.group?.isArchived == true)
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.isArchived == true)
        model.toggleArchived()
        #expect(model.group?.isArchived == false)
    }

    @Test func deleteRemovesTheGroupAndItsExpenses() throws {
        let fixture = try Fixture()
        try fixture.addExpense()
        let model = makeModel(fixture)
        #expect(model.delete())
        #expect(try fixture.services.groups.group(id: fixture.group.id) == nil)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)
    }

    @Test func savingKeepsAnArchivedGroupArchived() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.toggleArchived()
        model.name = "Renamed"
        try model.save()
        let saved = try #require(try fixture.services.groups.group(id: fixture.group.id))
        #expect(saved.isArchived)
        #expect(saved.name == "Renamed")
    }
}
