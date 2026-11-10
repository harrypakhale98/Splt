import Foundation
import SpltCore
import Testing
@testable import Splt

private struct FakeReader: SearchIntentReader {
    var isAvailable = true
    var reading = SearchIntentReading()
    var fails = false

    func read(_ query: String, names: [String]) async throws -> SearchIntentReading {
        if fails { throw OnDeviceModel.TimedOut() }
        return reading
    }
}

@MainActor
@Suite("Search model")
struct SearchModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func model(
        _ fixture: Fixture, reader: FakeReader = FakeReader(isAvailable: false),
        leftGroups: LeftGroupsStore = isolatedLeftGroups()
    ) -> SearchModel {
        SearchModel(
            services: fixture.services,
            recentStore: RecentSearchesStore(defaults: isolatedDefaults()),
            visibility: FriendVisibilityStore(defaults: isolatedDefaults()),
            leftGroups: leftGroups,
            reader: reader,
            now: { Date(timeIntervalSince1970: 1_781_524_800) },
            calendar: calendar
        )
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func scene() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner at Joe's", cents: 6000, paidBy: fixture.sam, date: date(3, 10))
        try fixture.addExpense("Dinner downtown", cents: 4500, paidBy: fixture.me, date: date(3, 20))
        try fixture.addExpense("Taxi home", cents: 1500, paidBy: fixture.sam, date: date(3, 21))
        try fixture.addExpense("Dinner again", cents: 5200, paidBy: fixture.sam, date: date(4, 2))
        return fixture
    }

    @Test func aGroupYouLeftAndItsExpensesAreNotFound() async throws {
        let fixture = try scene()
        let leftGroups = isolatedLeftGroups()
        let model = model(fixture, leftGroups: leftGroups)
        model.query = "flat"
        await model.search()
        #expect(model.groups.map(\.name) == ["Flat"])
        model.query = "taxi"
        await model.search()
        #expect(model.expenses.map(\.title) == ["Taxi home"])

        leftGroups.insert(fixture.group.id)
        model.query = "flat"
        await model.search()
        #expect(model.groups.isEmpty)
        model.query = "taxi"
        await model.search()
        #expect(model.expenses.isEmpty)
        model.query = "dinners paid by sam"
        await model.search()
        #expect(model.expenses.isEmpty)
    }

    @Test func plainWordsFindPeopleGroupsAndExpenses() async throws {
        let fixture = try scene()
        let model = model(fixture)
        model.query = "sam"
        await model.search()
        #expect(model.people.map(\.name) == ["Sam"])
        #expect(model.expenses.count == 4)
        #expect(model.understood == ["With Sam"])

        model.query = "flat"
        await model.search()
        #expect(model.groups.map(\.name) == ["Flat"])

        model.query = "taxi"
        await model.search()
        #expect(model.expenses.map(\.title) == ["Taxi home"])
    }

    @Test func answersTheExampleQuestion() async throws {
        let fixture = try scene()
        let model = model(fixture)
        model.query = "dinners Sam paid in March"
        await model.search()
        #expect(model.expenses.map(\.title) == ["Dinner at Joe's"])
        #expect(model.understood.contains("Dining"))
        #expect(model.understood.contains("Paid by Sam"))
        #expect(model.understood.contains { $0.contains("March") })
    }

    @Test func amountQuestionsFilterBySize() async throws {
        let fixture = try scene()
        let model = model(fixture)
        model.query = "dinner over 50"
        await model.search()
        #expect(Set(model.expenses.map(\.title)) == ["Dinner at Joe's", "Dinner again"])
    }

    @Test func emptyQueryClearsTheResults() async throws {
        let fixture = try scene()
        let model = model(fixture)
        model.query = "taxi"
        await model.search()
        #expect(!model.isEmpty)
        model.query = "   "
        await model.search()
        #expect(model.isEmpty)
        #expect(!model.hasSearched)
    }

    @Test func noMatchesSaysSo() async throws {
        let fixture = try scene()
        let model = model(fixture)
        model.query = "zebra"
        await model.search()
        #expect(model.isEmpty)
        #expect(model.hasSearched)
    }

    @Test func blockedPeopleAreLeftOut() async throws {
        let fixture = try scene()
        let visibility = FriendVisibilityStore(defaults: isolatedDefaults())
        visibility.set(.blocked, for: fixture.sam.id)
        let model = SearchModel(
            services: fixture.services, recentStore: RecentSearchesStore(defaults: isolatedDefaults()),
            visibility: visibility, reader: FakeReader(isAvailable: false)
        )
        model.query = "sam"
        await model.search()
        #expect(model.people.isEmpty)
    }

    @Test func theModelHelpsWhenTheRulesCannotReadTheQuestion() async throws {
        let fixture = try scene()
        var reading = SearchIntentReading()
        reading.month = 3
        let model = model(fixture, reader: FakeReader(reading: reading))
        model.query = "pizza from the third month"
        await model.search()
        #expect(Set(model.expenses.map(\.title)) == ["Dinner at Joe's", "Dinner downtown", "Taxi home"])
        #expect(model.understood.contains { $0.contains("March") })
    }

    @Test func aFailingModelFallsBackToPlainResults() async throws {
        let fixture = try scene()
        let model = model(fixture, reader: FakeReader(fails: true))
        model.query = "something with nothing here"
        await model.search()
        #expect(model.expenses.isEmpty)
        #expect(model.hasSearched)
    }

    @Test func recentSearchesAreRemembered() throws {
        let fixture = try Fixture()
        let model = model(fixture)
        model.query = "  taxi   home "
        model.remember()
        #expect(model.recents == ["taxi home"])
        model.clearRecents()
        #expect(model.recents.isEmpty)
    }
}

@Suite("Search intent validation")
struct SearchIntentValidatorTests {
    private let sam = Person(name: "Sam Rivera")
    private let maya = Person(name: "Maya Chen")
    private let now = Date(timeIntervalSince1970: 1_781_524_800)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func validator() -> SearchIntentValidator {
        SearchIntentValidator(people: [sam, maya], now: now, calendar: calendar)
    }

    @Test func keepsOnlyWhatIsWrittenInTheQuestion() {
        var reading = SearchIntentReading()
        reading.words = ["pizza", "invented"]
        reading.paidBy = "Sam"
        reading.withPerson = "Nobody"
        let filter = validator().filter(from: reading, query: "pizza that Sam paid for")
        #expect(filter.terms == ["pizza"])
        #expect(filter.payer == sam.id)
        #expect(filter.participant == nil)
    }

    @Test func rejectsPeopleThatWereNotWritten() {
        var reading = SearchIntentReading()
        reading.paidBy = "Maya"
        let filter = validator().filter(from: reading, query: "dinner last week")
        #expect(filter.payer == nil)
    }

    @Test func checksCategoriesMonthsAndYears() {
        var reading = SearchIntentReading()
        reading.category = "dining"
        reading.month = 3
        let filter = validator().filter(from: reading, query: "dinners in march")
        #expect(filter.category == .dining)
        #expect(filter.period != nil)

        var bad = SearchIntentReading()
        bad.category = "spaceships"
        bad.month = 13
        bad.year = 3000
        #expect(!validator().filter(from: bad, query: "x").isStructured)

        var general = SearchIntentReading()
        general.category = "general"
        #expect(validator().filter(from: general, query: "x").category == nil)
    }

    @Test func aYearAloneCoversTheWholeYear() throws {
        var reading = SearchIntentReading()
        reading.year = 2024
        let period = try #require(validator().filter(from: reading, query: "2024").period)
        #expect(calendar.component(.month, from: period.lowerBound) == 1)
        #expect(calendar.dateComponents([.month], from: period.lowerBound, to: period.upperBound).month == 12)
    }

    @Test func amountsCarryOver() {
        var reading = SearchIntentReading()
        reading.minimumAmount = 20
        reading.maximumAmount = 80
        let filter = validator().filter(from: reading, query: "between 20 and 80")
        #expect(filter.minAmount == 20 && filter.maxAmount == 80)
    }
}

@Suite("Recent searches")
struct RecentSearchesStoreTests {
    @Test func keepsNewestFirstWithoutDuplicates() {
        let store = RecentSearchesStore(defaults: isolatedDefaults())
        store.add("taxi")
        store.add("dinner")
        store.add("TAXI")
        #expect(store.queries == ["TAXI", "dinner"])
    }

    @Test func ignoresShortQueriesAndCapsTheList() {
        let store = RecentSearchesStore(defaults: isolatedDefaults())
        store.add("a")
        #expect(store.queries.isEmpty)
        for number in 0..<20 { store.add("query \(number)") }
        #expect(store.queries.count == RecentSearchesStore.limit)
        #expect(store.queries.first == "query 19")
    }
}
