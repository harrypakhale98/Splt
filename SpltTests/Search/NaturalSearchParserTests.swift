import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Natural search parser")
struct NaturalSearchParserTests {
    private let sam = Person(name: "Sam Rivera")
    private let maya = Person(name: "Maya Chen")
    private let me = Person(name: "Jamie", kind: .me)
    private let samJones = Person(name: "Sam Jones")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 15 June 2026.
    private let now = Date(timeIntervalSince1970: 1_781_524_800)

    private func parser(_ people: [Person]? = nil) -> NaturalSearchParser {
        NaturalSearchParser(people: people ?? [me, sam, maya], now: now, calendar: calendar)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func readsTheExampleQuestion() {
        let filter = parser().parse("dinners Sam paid in March")
        #expect(filter.category == .dining)
        #expect(filter.payer == sam.id)
        #expect(filter.participant == nil)
        #expect(filter.period == day(2026, 3, 1)..<day(2026, 4, 1))
        #expect(filter.terms.isEmpty)
        #expect(filter.isStructured)
    }

    @Test func aMonthAfterTodayMeansLastYear() {
        let filter = parser().parse("rent in November")
        #expect(filter.period == day(2025, 11, 1)..<day(2025, 12, 1))
        #expect(filter.category == .rent)
    }

    @Test func anExplicitYearWins() {
        #expect(parser().parse("hotel march 2024").period == day(2024, 3, 1)..<day(2024, 4, 1))
        #expect(parser().parse("everything in 2025").period == day(2025, 1, 1)..<day(2026, 1, 1))
    }

    @Test func readsRelativePeriods() {
        #expect(parser().parse("coffee yesterday").period == day(2026, 6, 14)..<day(2026, 6, 15))
        #expect(parser().parse("coffee today").period == day(2026, 6, 15)..<day(2026, 6, 16))
        #expect(parser().parse("taxi last month").period == day(2026, 5, 1)..<day(2026, 6, 1))
        #expect(parser().parse("taxi this month").period == day(2026, 6, 1)..<day(2026, 7, 1))
        #expect(parser().parse("gifts last year").period == day(2025, 1, 1)..<day(2026, 1, 1))
        #expect(parser().parse("spent last 10 days").period == day(2026, 6, 5)..<day(2026, 6, 16))
        #expect(parser().parse("past 2 weeks").period == day(2026, 6, 1)..<day(2026, 6, 16))
    }

    @Test func thisAndLastWeekFollowTheCalendar() throws {
        let this = try #require(parser().parse("this week").period)
        let last = try #require(parser().parse("last week").period)
        #expect(this.contains(now))
        #expect(last.upperBound == this.lowerBound)
    }

    @Test func mayIsOnlyAMonthWhenItIsClear() {
        #expect(parser().parse("dinner in may").period == day(2026, 5, 1)..<day(2026, 6, 1))
        #expect(parser().parse("may 2025").period == day(2025, 5, 1)..<day(2025, 6, 1))
        let verb = parser().parse("you may owe pizza")
        #expect(verb.period == nil)
        #expect(verb.terms.contains("may"))
    }

    @Test func readsAmountBounds() {
        let over = parser().parse("dinner over $50")
        #expect(over.minAmount == 50 && over.maxAmount == nil)
        let under = parser().parse("groceries under 20.50")
        #expect(under.maxAmount == Decimal(string: "20.50"))
        #expect(parser().parse("more than 100").minAmount == 100)
        #expect(parser().parse("less than 15").maxAmount == 15)
        #expect(parser().parse("at least 9").minAmount == 9)
        let both = parser().parse("over 10 under 40")
        #expect(both.minAmount == 10 && both.maxAmount == 40)
    }

    @Test func tellsPayersFromParticipants() {
        #expect(parser().parse("paid by Maya").payer == maya.id)
        #expect(parser().parse("Maya paid").payer == maya.id)
        #expect(parser().parse("expenses by maya").payer == maya.id)
        let with = parser().parse("dinner with Maya")
        #expect(with.participant == maya.id && with.payer == nil)
        #expect(with.terms.isEmpty)
        #expect(parser().parse("Maya").participant == maya.id)
        #expect(parser().parse("I paid for lunch").payer == me.id)
    }

    @Test func fullNamesPickTheRightPerson() {
        let people = [me, sam, samJones]
        #expect(parser(people).parse("Sam Jones paid").payer == samJones.id)
        #expect(parser(people).parse("Sam Rivera paid").payer == sam.id)
        // two people share a first name, so a bare first name is left as a plain word
        let ambiguous = parser(people).parse("Sam")
        #expect(ambiguous.participant == nil)
        #expect(ambiguous.terms == ["Sam"])
    }

    @Test func peopleNamesAreCaseAndAccentInsensitive() {
        let jose = Person(name: "José Álvarez")
        let filter = parser([me, jose]).parse("jose paid")
        #expect(filter.payer == jose.id)
    }

    @Test func plainWordsStayPlain() {
        let filter = parser().parse("pizza friday")
        #expect(!filter.isStructured)
        #expect(filter.terms == ["pizza", "friday"])
        #expect(parser().parse("").terms.isEmpty)
        #expect(!parser().parse("   ").isStructured)
    }

    @Test func aCategoryWordAlsoMatchesTheTitle() {
        let filter = parser().parse("dinner")
        #expect(filter.category == .dining)
        #expect(filter.categoryWord == "dinner")
        let general = Expense(
            title: "Dinner at Joe's", total: usdAmount(5000), date: now, category: .general,
            paidBy: sam.id, split: .equal(participants: [sam.id, maya.id])
        )
        #expect(filter.matches(general, groupName: nil, names: [:]))
        let rent = Expense(
            title: "Flat", total: usdAmount(5000), date: now, category: .rent,
            paidBy: sam.id, split: .equal(participants: [sam.id, maya.id])
        )
        #expect(!filter.matches(rent, groupName: nil, names: [:]))
    }

    @Test func leftoverWordsBecomeTerms() {
        let filter = parser().parse("show me all pizza Maya paid in March")
        #expect(filter.terms == ["pizza"])
        #expect(filter.payer == maya.id)
        #expect(filter.category == nil)
        #expect(parser().parse("show me dinners").category == .dining)
        #expect(parser().parse("tickets to a show").category == .entertainment)
    }
}

@Suite("Search filter")
struct SearchFilterTests {
    private let sam = PersonID()
    private let maya = PersonID()
    private let day = Date(timeIntervalSince1970: 1_781_524_800)

    private func expense(
        _ title: String, cents: Int64 = 5000, category: ExpenseCategory = .dining, paidBy: PersonID? = nil, at date: Date? = nil
    ) -> Expense {
        Expense(
            title: title, total: usdAmount(cents), date: date ?? day, category: category,
            paidBy: paidBy ?? sam, split: .equal(participants: [sam, maya])
        )
    }

    @Test func matchesEveryPartOfTheQuestion() {
        var filter = SearchFilter()
        filter.category = .dining
        filter.payer = sam
        filter.period = day.addingTimeInterval(-86_400)..<day.addingTimeInterval(86_400)
        #expect(filter.matches(expense("Tapas"), groupName: nil, names: [:]))
        #expect(!filter.matches(expense("Tapas", paidBy: maya), groupName: nil, names: [:]))
        #expect(!filter.matches(expense("Tapas", at: day.addingTimeInterval(5 * 86_400)), groupName: nil, names: [:]))
        #expect(!filter.matches(expense("Bus", category: .transport), groupName: nil, names: [:]))
    }

    @Test func comparesAmountsInMajorUnits() {
        var filter = SearchFilter()
        filter.minAmount = 40
        filter.maxAmount = 60
        #expect(filter.matches(expense("A", cents: 5000), groupName: nil, names: [:]))
        #expect(filter.matches(expense("B", cents: 4000), groupName: nil, names: [:]))
        #expect(!filter.matches(expense("C", cents: 3999), groupName: nil, names: [:]))
        #expect(!filter.matches(expense("D", cents: 6001), groupName: nil, names: [:]))
        let yen = Expense(
            title: "Ramen", total: Money(minorUnits: 5000, currencyCode: "JPY"), date: day, paidBy: sam,
            split: .equal(participants: [sam, maya])
        )
        filter.maxAmount = 6000
        filter.minAmount = 4000
        #expect(filter.matches(yen, groupName: nil, names: [:]))
    }

    @Test func termsLookAtTitleNoteGroupAndPeople() {
        var filter = SearchFilter()
        filter.terms = ["lisbon", "maya"]
        #expect(filter.matches(expense("Pastel"), groupName: "Lisbon Trip", names: [maya: "Maya Chen"]))
        #expect(!filter.matches(expense("Pastel"), groupName: "Flat", names: [maya: "Maya Chen"]))
        #expect(!filter.matches(expense("Pastel"), groupName: "Lisbon Trip", names: [:]))
    }

    @Test func refundsCountByTheirSize() {
        var filter = SearchFilter()
        filter.minAmount = 10
        let refund = Expense(
            title: "Refund", total: usdAmount(-2000), date: day, paidBy: sam,
            split: .equal(participants: [sam, maya])
        )
        #expect(filter.matches(refund, groupName: nil, names: [:]))
    }

    @Test func plainFiltersAreNotStructured() {
        var filter = SearchFilter()
        filter.terms = ["pizza"]
        #expect(!filter.isStructured)
        filter.payer = sam
        #expect(filter.isStructured)
    }
}
