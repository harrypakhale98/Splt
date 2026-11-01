import Foundation
import SpltCore
import Testing
import UIKit
@testable import Splt

@MainActor
@Suite("Create group")
struct CreateGroupViewModelTests {
    private func makeModel(_ services: DataServices, today: Date = utcDate(2026, 5, 8)) -> CreateGroupViewModel {
        CreateGroupViewModel(services: services, defaultCurrencyCode: "EUR", today: today, calendar: GroupsTestCalendar.utc)
    }

    @Test func needsAName() throws {
        let model = makeModel(try DataServices.inMemory())
        #expect(!model.canCreate)
        model.name = "   "
        #expect(!model.canCreate)
        model.name = "Flat"
        #expect(model.canCreate)
    }

    @Test func startsWithTheDefaultCurrency() throws {
        #expect(makeModel(try DataServices.inMemory()).currencyCode == "EUR")
    }

    @Test func aTripCannotEndBeforeItStarts() throws {
        let model = makeModel(try DataServices.inMemory())
        model.name = "Lisbon"
        model.selectTemplate(.trip)
        #expect(model.canCreate)
        model.tripEnd = model.tripStart.addingTimeInterval(-86_400)
        #expect(!model.canCreate)
    }

    @Test func movingTheStartPastTheEndMovesTheEnd() throws {
        let model = makeModel(try DataServices.inMemory())
        model.selectTemplate(.trip)
        model.tripStart = model.tripEnd.addingTimeInterval(86_400 * 3)
        model.tripStartChanged()
        #expect(model.tripEnd == model.tripStart)
    }

    @Test func creatingAddsYouAndPlaceholdersForNamedPeople() throws {
        let services = try DataServices.inMemory()
        let model = makeModel(services)
        model.name = "Weekend"
        #expect(model.addMember(named: "  Alex "))
        #expect(model.addMember(named: "Jo", contactHint: "jo@example.com"))

        let id = try model.create()
        let group = try #require(try services.groups.group(id: id))
        #expect(group.name == "Weekend")
        #expect(group.currencyCode == "EUR")
        #expect(group.memberIDs.count == 3)

        let me = try #require(try services.people.me())
        #expect(group.memberIDs.first == me.id)
        let others = try services.people.people(ids: Array(group.memberIDs.dropFirst()))
        #expect(others.map(\.name) == ["Alex", "Jo"])
        #expect(others.allSatisfy { $0.isPlaceholder })
        #expect(others.last?.contactHint == "jo@example.com")
    }

    @Test func duplicateAndBlankNamesAreIgnored() throws {
        let model = makeModel(try DataServices.inMemory())
        #expect(model.addMember(named: "Alex"))
        #expect(!model.addMember(named: "alex"))
        #expect(!model.addMember(named: "   "))
        #expect(model.members.count == 1)
    }

    @Test func friendsAreReusedNotDuplicated() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture.services)
        #expect(Set(model.friends.map(\.id)) == [fixture.sam.id, fixture.priya.id])
        model.name = "Dinner club"
        model.toggle(fixture.sam)
        #expect(model.isSelected(fixture.sam))
        let peopleBefore = try fixture.services.people.allPeople().count

        let id = try model.create()
        let group = try #require(try fixture.services.groups.group(id: id))
        #expect(group.memberIDs == [fixture.me.id, fixture.sam.id])
        #expect(try fixture.services.people.allPeople().count == peopleBefore)

        model.toggle(fixture.sam)
        #expect(!model.isSelected(fixture.sam))
    }

    @Test func removingAMemberDropsItFromTheList() throws {
        let model = makeModel(try DataServices.inMemory())
        model.addMember(named: "Alex")
        model.addMember(named: "Jo")
        model.removeMembers(at: IndexSet(integer: 0))
        #expect(model.members.map(\.name) == ["Jo"])
    }

    @Test func templatesPickKindAndSymbol() throws {
        let services = try DataServices.inMemory()
        let model = makeModel(services)
        model.name = "Place"

        model.selectTemplate(.home)
        #expect(model.template.kind == .standard)
        #expect(model.symbol == "house.fill")

        model.selectTemplate(.couple)
        #expect(model.symbol == "heart.fill")

        let id = try model.create()
        let group = try #require(try services.groups.group(id: id))
        #expect(group.kind == .couple)
        #expect(group.tripStart == nil && group.tripEnd == nil)
    }

    @Test func tripsKeepTheirDates() throws {
        let services = try DataServices.inMemory()
        let model = makeModel(services, today: utcDate(2026, 5, 8))
        model.name = "Lisbon"
        model.selectTemplate(.trip)
        let id = try model.create()
        let group = try #require(try services.groups.group(id: id))
        #expect(group.kind == .trip)
        #expect(group.tripStart == GroupsTestCalendar.utc.startOfDay(for: utcDate(2026, 5, 8)))
        #expect(group.tripEnd == GroupsTestCalendar.utc.startOfDay(for: utcDate(2026, 5, 14)))
    }

    @Test func theNameSuggestsASymbolUntilOneIsChosen() throws {
        let model = makeModel(try DataServices.inMemory())
        model.name = "Ski weekend"
        model.nameChanged()
        #expect(model.symbol == "figure.skiing.downhill")

        model.chooseSymbol("star.fill")
        model.name = "Beach days"
        model.nameChanged()
        model.selectTemplate(.trip)
        #expect(model.symbol == "star.fill")
    }

    @Test func simplifyDebtsIsSaved() throws {
        let services = try DataServices.inMemory()
        let model = makeModel(services)
        model.name = "Flat"
        model.simplifiesDebts = false
        let id = try model.create()
        #expect(try services.groups.group(id: id)?.simplifiesDebts == false)
    }

    @Test func creatingGroupsDoesNotNeedAnExistingProfile() throws {
        let services = try DataServices.inMemory()
        #expect(try services.people.me() == nil)
        let model = makeModel(services)
        model.name = "First"
        _ = try model.create()
        #expect(try services.people.me() != nil)
    }
}

@Suite("Symbols")
struct GroupSymbolTests {
    @Test func suggestsFromKeywordsAndPlurals() {
        #expect(GroupSymbolSuggester.symbol(for: "Lisbon Trip") == "airplane")
        #expect(GroupSymbolSuggester.symbol(for: "Flat 4B") == "house.fill")
        #expect(GroupSymbolSuggester.symbol(for: "Weekly groceries") == "cart.fill")
        #expect(GroupSymbolSuggester.symbol(for: "Birthdays") == "gift.fill")
        #expect(GroupSymbolSuggester.symbol(for: "Zzz") == nil)
        #expect(GroupSymbolSuggester.symbol(for: "") == nil)
    }

    @Test func everyOfferedSymbolExists() {
        for symbol in GroupSymbols.all {
            #expect(UIImage(systemName: symbol) != nil, "missing symbol \(symbol)")
        }
        #expect(Set(GroupSymbols.all).count == GroupSymbols.all.count)
    }

    @Test func everyTemplateSymbolAndSuggestionExists() {
        for template in GroupTemplate.allCases {
            #expect(UIImage(systemName: template.defaultSymbol) != nil)
        }
    }
}
