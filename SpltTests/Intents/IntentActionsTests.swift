import AppIntents
import CoreSpotlight
import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Intent actions")
struct IntentActionsTests {
    private let english = Locale(identifier: "en_US")

    private func actions(_ fixture: Fixture) -> IntentActions {
        IntentActions(services: fixture.services, now: { fixture.clock.start })
    }

    @Test func anUnlockedDeviceIsNeededToReadOrChangeMoney() {
        #expect(AddExpenseIntent.authenticationPolicy == .requiresAuthentication)
        #expect(ViewBalanceIntent.authenticationPolicy == .requiresAuthentication)
    }

    @Test func addsAnExpenseToTheNewestGroupSplitEqually() throws {
        let fixture = try Fixture()
        let added = try actions(fixture).addExpense(title: "Pizza", amount: 30, group: nil, friend: nil)
        #expect(added.amount == usdAmount(3000))
        #expect(added.groupName == "Flat")
        let stored = try #require(try fixture.services.expenses.expenses(in: fixture.group.id).first)
        #expect(stored.title == "Pizza")
        #expect(stored.payers == [fixture.me.id: usdAmount(3000)])
        #expect(stored.split.participants == fixture.everyone)
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).total == [usdAmount(1000)])
    }

    @Test func addsToAChosenGroup() throws {
        let fixture = try Fixture()
        let trip = SplitGroup(name: "Trip", currencyCode: "EUR", memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(trip)
        let added = try actions(fixture).addExpense(title: "Museum", amount: 24.5, group: trip.id.rawValue, friend: nil)
        #expect(added.amount == Money(minorUnits: 2450, currencyCode: "EUR"))
        #expect(try fixture.services.expenses.expenses(in: trip.id).count == 1)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)
    }

    @Test func addsToTheDirectGroupWithAFriend() throws {
        let fixture = try Fixture()
        let added = try actions(fixture).addExpense(title: "Coffee", amount: 8, group: nil, friend: fixture.sam.id.rawValue)
        #expect(added.groupName == "Direct expenses")
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.total == [usdAmount(400)])
    }

    @Test func refusesBadInput() throws {
        let fixture = try Fixture()
        let actions = actions(fixture)
        #expect(throws: IntentActions.Failure.badAmount) {
            try actions.addExpense(title: "Free", amount: 0, group: nil, friend: nil)
        }
        #expect(throws: IntentActions.Failure.badAmount) {
            try actions.addExpense(title: "Negative", amount: -5, group: nil, friend: nil)
        }
        #expect(throws: IntentActions.Failure.unknownGroup) {
            try actions.addExpense(title: "Lost", amount: 5, group: UUID(), friend: nil)
        }
        #expect(throws: IntentActions.Failure.unknownFriend) {
            try actions.addExpense(title: "Lost", amount: 5, group: nil, friend: UUID())
        }
    }

    @Test func needsAGroupWhenNoneExists() throws {
        let services = try DataServices.inMemory()
        _ = try services.people.ensureMe(name: "Me")
        #expect(throws: IntentActions.Failure.noGroup) {
            try IntentActions(services: services).addExpense(title: "Lunch", amount: 10, group: nil, friend: nil)
        }
    }

    @Test func blankTitlesGetADefault() throws {
        let fixture = try Fixture()
        let added = try actions(fixture).addExpense(title: "   ", amount: 5, group: nil, friend: nil)
        #expect(added.title == "Expense")
    }

    @Test func describesBalancesWithAFriend() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let actions = actions(fixture)
        #expect(try actions.balanceSentence(friend: fixture.sam.id.rawValue, group: nil, locale: english) == "Sam owes you $10.00.")
        try fixture.addExpense("Taxi", cents: 5000, paidBy: fixture.sam, splitBetween: [fixture.me.id, fixture.sam.id])
        #expect(try actions.balanceSentence(friend: fixture.sam.id.rawValue, group: nil, locale: english) == "You owe Sam $15.00.")
    }

    @Test func describesGroupAndOverallBalances() throws {
        let fixture = try Fixture()
        let actions = actions(fixture)
        #expect(try actions.balanceSentence(friend: nil, group: fixture.group.id.rawValue, locale: english) == "You are settled up in Flat.")
        #expect(try actions.balanceSentence(friend: nil, group: nil, locale: english) == "You are all settled up.")
        try fixture.addExpense("Dinner", cents: 3000)
        #expect(try actions.balanceSentence(friend: nil, group: fixture.group.id.rawValue, locale: english) == "In Flat, you are owed $20.00.")
        #expect(try actions.balanceSentence(friend: nil, group: nil, locale: english) == "Friends owe you $20.00.")
    }

    @Test func unknownTargetsThrow() throws {
        let fixture = try Fixture()
        #expect(throws: IntentActions.Failure.unknownFriend) {
            try actions(fixture).balanceSentence(friend: UUID(), group: nil)
        }
        #expect(throws: IntentActions.Failure.unknownGroup) {
            try actions(fixture).balanceSentence(friend: nil, group: UUID())
        }
    }

    @Test func settledFriendsAreSaidSo() {
        #expect(IntentActions.sentence(about: "Sam", amounts: [], locale: english) == "You and Sam are settled up.")
        #expect(IntentActions.sentence(about: "Sam", amounts: [usdAmount(100), Money(minorUnits: -200, currencyCode: "EUR")], locale: english)
            == "Sam owes you $1.00, and you owe Sam \u{20AC}2.00.")
    }
}

@Suite("Intent amounts")
struct IntentAmountTests {
    @Test func roundsToTheCurrencysSmallestUnit() {
        #expect(IntentAmount.money(from: 12.35, currencyCode: "USD") == usdAmount(1235))
        #expect(IntentAmount.money(from: 19.999, currencyCode: "USD") == usdAmount(2000))
        #expect(IntentAmount.money(from: 1500, currencyCode: "JPY") == Money(minorUnits: 1500, currencyCode: "JPY"))
        #expect(IntentAmount.money(from: 1.2345, currencyCode: "KWD") == Money(minorUnits: 1235, currencyCode: "KWD"))
    }

    @Test func refusesAmountsThatAreNotPositiveMoney() {
        #expect(IntentAmount.money(from: 0, currencyCode: "USD") == nil)
        #expect(IntentAmount.money(from: -1, currencyCode: "USD") == nil)
        #expect(IntentAmount.money(from: 0.004, currencyCode: "USD") == nil)
        #expect(IntentAmount.money(from: .nan, currencyCode: "USD") == nil)
        #expect(IntentAmount.money(from: .infinity, currencyCode: "USD") == nil)
    }
}

@MainActor
@Suite("Intent entities")
struct IntentEntityTests {
    @Test func friendsExcludeYouAndBlockedPeople() throws {
        let fixture = try Fixture()
        let visibility = FriendVisibilityStore(defaults: isolatedDefaults())
        visibility.set(.blocked, for: fixture.priya.id)
        let friends = IntentFriends.all(services: fixture.services, visibility: visibility)
        #expect(friends.map(\.name) == ["Sam"])
        #expect(friends.first?.id == fixture.sam.id.rawValue)
    }

    @Test func groupsSkipHiddenFriendGroups() throws {
        let fixture = try Fixture()
        try fixture.services.groups.create(SplitGroup(name: "Sam", currencyCode: "USD", kind: .friend, memberIDs: [fixture.me.id, fixture.sam.id]))
        #expect(IntentGroups.all(services: fixture.services).map(\.name) == ["Flat"])
    }

    @Test func entitiesCarryNameAndId() {
        let person = Person(name: "Maya Chen")
        let entity = FriendEntity(person)
        #expect(entity.id == person.id.rawValue)
        #expect(entity.name == "Maya Chen")
        let group = SplitGroup(name: "Trip", currencyCode: "EUR")
        #expect(GroupEntity(group).id == group.id.rawValue)
    }

    @Test func settleUpOpensTheFriendThroughTheDeepLink() throws {
        let id = UUID()
        let url = DeepLink.settle(id).url
        #expect(DeepLink(url: url) == .settle(id))
    }
}

private final class RecordingIndex: FriendSearchIndex, @unchecked Sendable {
    private(set) var replaced: [[CSSearchableItem]] = []
    var fails = false

    func replaceAll(with items: [CSSearchableItem]) async throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        replaced.append(items)
    }
}

@MainActor
@Suite("Friend Spotlight")
struct FriendSpotlightTests {
    @Test func identifiersRoundTrip() {
        let id = PersonID()
        #expect(FriendSpotlight.personID(fromIdentifier: FriendSpotlight.identifier(for: id)) == id)
        #expect(FriendSpotlight.personID(fromIdentifier: "group.\(id)") == nil)
        #expect(FriendSpotlight.personID(fromIdentifier: "friend.nope") == nil)
    }

    @Test func indexesFriendsButNotYouOrBlockedPeople() {
        let me = Person(name: "Me", kind: .me)
        let ana = Person(name: "Ana")
        let ben = Person(name: "Ben")
        #expect(!FriendSpotlight.isIndexed(me, blocked: []))
        #expect(FriendSpotlight.isIndexed(ana, blocked: []))
        #expect(!FriendSpotlight.isIndexed(ben, blocked: [ben.id]))
    }

    @Test func itemsCarryTheNameAndIdentifier() {
        let ana = Person(name: "Ana Pena", kind: .placeholder)
        let item = FriendSpotlight.item(for: ana)
        #expect(item.uniqueIdentifier == FriendSpotlight.identifier(for: ana.id))
        #expect(item.domainIdentifier == FriendSpotlight.domain)
        #expect(item.attributeSet.title == "Ana Pena")
        #expect(item.attributeSet.contentDescription?.contains("not on Splt yet") == true)
    }

    @Test func theIndexerReplacesEverythingAndSkipsBlockedPeople() async {
        let index = RecordingIndex()
        let ana = Person(name: "Ana"), ben = Person(name: "Ben"), me = Person(name: "Me", kind: .me)
        let count = await FriendIndexer(index: index).update(friends: [ana, ben, me], blocked: [ben.id])
        #expect(count == 1)
        #expect(index.replaced.count == 1)
        #expect(index.replaced.first?.first?.uniqueIdentifier == FriendSpotlight.identifier(for: ana.id))
    }

    @Test func aFailingIndexIndexesNothing() async {
        let index = RecordingIndex()
        index.fails = true
        #expect(await FriendIndexer(index: index).update(friends: [Person(name: "Ana")], blocked: []) == 0)
    }
}
