import SpltCore
import Testing
@testable import Splt

@Suite("Quick add rules")
struct QuickAddParserTests {
    private let context = QuickAddContext(candidateNames: ["Sam Carter", "Priya Shah", "Alex"], defaultCurrencyCode: "USD")
    private let parser = RuleBasedQuickAddParser()

    private func parse(_ text: String) -> QuickAddDraft {
        parser.parseNow(text, context: context)
    }

    @Test func readsTheFullExample() {
        let draft = parse("dinner 60 with Sam and Priya, I paid, Priya owes 10 less")
        #expect(draft.title == "Dinner")
        #expect(draft.amount == Money(minorUnits: 6000, currencyCode: "USD"))
        #expect(draft.currencyHint == nil)
        #expect(Set(draft.participantNames) == ["Sam Carter", "Priya Shah"])
        #expect(draft.payer == .me)
        #expect(draft.splitHint == .adjustments([
            QuickAddShare(name: "Priya Shah", amount: Money(minorUnits: -1000, currencyCode: "USD"))
        ]))
        #expect(draft.category == .food)
        #expect(draft.source == .rules)
    }

    @Test func readsDictatedNumberWordsAndLowercaseNames() {
        let draft = parse("dinner sixty with sam and priya i paid")
        #expect(draft.amount?.minorUnits == 6000)
        #expect(Set(draft.participantNames) == ["Sam Carter", "Priya Shah"])
        #expect(draft.payer == .me)
    }

    @Test func currencySymbolsSetTheHint() {
        let euro = parse("coffee €4,80")
        #expect(euro.amount == Money(minorUnits: 480, currencyCode: "EUR"))
        #expect(euro.currencyHint == "EUR")
        let yen = parse("ramen ¥1200")
        #expect(yen.amount == Money(minorUnits: 1200, currencyCode: "JPY"))
        let dollars = parse("movie night 45 dollars between Sam, Alex and Priya")
        #expect(dollars.amount?.minorUnits == 4500)
        #expect(dollars.currencyHint == "USD")
        #expect(Set(dollars.participantNames) == ["Sam Carter", "Alex", "Priya Shah"])
        #expect(dollars.title == "Movie night")
    }

    @Test func countsOfPeopleAndTableNumbersAreNotPrices() {
        #expect(parse("pizza for 4 people 36").amount?.minorUnits == 3600)
        #expect(parse("dinner at table 12 for 85 with Jordan").amount?.minorUnits == 8500)
        #expect(parse("airbnb 480 for 3 nights with Sam and Alex").amount?.minorUnits == 48_000)
    }

    @Test func thousandsAndSuffixesParse() {
        #expect(parse("rent 1,250.00").amount?.minorUnits == 125_000)
        #expect(parse("hotel 1.2k with Priya").amount?.minorUnits == 120_000)
    }

    @Test func payerVariants() {
        #expect(parse("Paid 25 for lunch").payer == .me)
        #expect(parse("gas 45 I covered it").payer == .me)
        #expect(parse("groceries 52.30, paid by Alex").payer == .person("Alex"))
        let named = parse("Sam Carter paid for drinks 30")
        #expect(named.payer == .person("Sam Carter"))
        #expect(named.payerName == "Sam Carter")
        #expect(named.participantNames == ["Sam Carter"])
        #expect(named.title == "Drinks")
    }

    @Test func splitHints() {
        #expect(parse("airbnb 480 with Sam and Alex, split evenly").splitHint == .equal)
        let more = parse("dinner 120 usd Priya pays 20 more")
        #expect(more.splitHint == .adjustments([
            QuickAddShare(name: "Priya Shah", amount: Money(minorUnits: 2000, currencyCode: "USD"))
        ]))
        let exact = parse("rent 1,250.00 Alex owes 400")
        #expect(exact.amount?.minorUnits == 125_000)
        #expect(exact.splitHint == .exactAmounts([
            QuickAddShare(name: "Alex", amount: Money(minorUnits: 40_000, currencyCode: "USD"))
        ]))
        #expect(parse("dinner 60").splitHint == nil)
    }

    @Test func newNamesAreKeptAndLowercaseUnknownWordsAreNot() {
        #expect(parse("dinner 60 with Jordan Lee and Alex").participantNames == ["Jordan Lee", "Alex"])
        let plain = parse("lunch with the team 25")
        #expect(plain.participantNames.isEmpty)
        #expect(plain.title == "Lunch with the team")
    }

    @Test func defaultCurrencyDecidesFractionDigits() {
        let yenContext = QuickAddContext(candidateNames: [], defaultCurrencyCode: "JPY")
        let draft = parser.parseNow("ramen 1200", context: yenContext)
        #expect(draft.amount == Money(minorUnits: 1200, currencyCode: "JPY"))
        #expect(draft.currencyHint == nil)
    }

    @Test func emptyAndAmountlessNotes() {
        #expect(parse("").isEmpty)
        let draft = parse("groceries")
        #expect(draft.amount == nil)
        #expect(draft.title == "Groceries")
        #expect(draft.category == .groceries)
    }

    @Test func asyncEntryPointMatchesTheSyncOne() async {
        let text = "Uber 18.50 with Alex"
        #expect(await parser.parse(text, context: context) == parse(text))
    }

    @Test func aSpaceBetweenThousandsIsRead() {
        let draft = parse("dinner 1 234,50 with Sam")
        #expect(draft.amount?.minorUnits == 123_450)
        #expect(draft.title == "Dinner")
        #expect(parse("rent 12 500.00").amount?.minorUnits == 1_250_000)
    }

    @Test func separateNumbersAreNotJoined() {
        #expect(parse("tickets 2 500 with Sam").amount?.minorUnits == 50_000)
        #expect(parse("snacks 3 12.50").amount?.minorUnits == 1250)
        #expect(parse("dinner at table 4 125.50").amount?.minorUnits == 12_550)
    }

    @Test func datesTimesAndYearsAreNotThePrice() {
        let lunch = parse("lunch 8 on March 15 with Sam")
        #expect(lunch.amount?.minorUnits == 800)
        #expect(lunch.title == "Lunch")
        #expect(parse("lunch 8 on 15 March with Sam").amount?.minorUnits == 800)
        #expect(parse("NYE 2026 dinner 120 with Sam").amount?.minorUnits == 12_000)
        #expect(parse("5k race entry 35 with Sam").amount?.minorUnits == 3500)
        #expect(parse("coffee 5 at 8 with Sam").amount?.minorUnits == 500)
    }

    @Test func aNumberThatLooksLikeADateIsStillThePriceWhenAlone() {
        #expect(parse("rent 2000 with Sam").amount?.minorUnits == 200_000)
        #expect(parse("lunch at 12 with Sam").amount?.minorUnits == 1200)
        #expect(parse("tickets for May 20").amount?.minorUnits == 2000)
        #expect(parse("trip 5k with Sam").amount?.minorUnits == 500_000)
        #expect(parse("deposit 2k for 12 months").amount?.minorUnits == 200_000)
        #expect(parse("spent 40 on 3 pizzas").amount?.minorUnits == 4000)
        #expect(parse("spent 40 on 3 pizzas").title == "3 pizzas")
    }

    @Test func aCapitalisedWordBeforeThePayerIsNotAFirstName() {
        let camping = parser.parseNow("Camping Sam paid 120", context: QuickAddContext(candidateNames: ["Sam"]))
        #expect(camping.payer == .person("Sam"))
        #expect(camping.participantNames == ["Sam"])
        #expect(camping.title == "Camping")
        #expect(camping.amount?.minorUnits == 12_000)

        let padel = parser.parseNow("Padel Sam paid 40", context: QuickAddContext())
        #expect(padel.payer == .person("Sam"))
        #expect(padel.participantNames == ["Sam"])
        #expect(padel.title == "Padel")
    }

    @Test func twoWordNamesStillReadAsOnePerson() {
        let members = QuickAddContext(candidateNames: ["Mary Ann", "Noah Quinn", "Ann"])
        let paid = parser.parseNow("Mary Ann paid 40 for lunch", context: members)
        #expect(paid.payer == .person("Mary Ann"))
        #expect(paid.title == "Lunch")
        #expect(parser.parseNow("dinner 60 with Noah Quinn and Mary Ann", context: members).participantNames == ["Noah Quinn", "Mary Ann"])
        // someone new, written in full, with other words left for the title
        let fresh = parse("Jordan Lee paid 40 for dinner")
        #expect(fresh.payer == .person("Jordan Lee"))
        #expect(fresh.title == "Dinner")
    }

    @Test func aPricePerPersonIsMultipliedOut() {
        let tickets = parse("tickets 12.50 each with Sam and Priya")
        #expect(tickets.amount?.minorUnits == 3750)
        #expect(tickets.title == "Tickets")
        #expect(parse("brunch 20 per person with Alex").amount?.minorUnits == 4000)
        let dinner = parse("dinner 30 a head with Sam, Priya and Alex")
        #expect(dinner.amount?.minorUnits == 12_000)
        #expect(dinner.title == "Dinner")
        #expect(parse("tacos $9 apiece with Sam").amount?.minorUnits == 1800)
    }

    @Test func aPricePerPersonStaysAsWrittenWithoutAHeadCount() {
        let alone = parse("tickets 12.50 each")
        #expect(alone.amount?.minorUnits == 1250)
        #expect(alone.title == "Tickets")
        #expect(parse("tickets 25 with Sam and Priya").amount?.minorUnits == 2500)
        #expect(parse("we each paid 20 for lunch with Sam").amount?.minorUnits == 2000)
    }
}
