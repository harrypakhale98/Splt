import SpltCore
import Testing
@testable import Splt

private struct StubReader: QuickAddReader {
    var isAvailable = true
    var reading: QuickAddReading?

    func read(_ text: String, context: QuickAddContext) async throws -> QuickAddReading {
        guard let reading else { throw OnDeviceModel.TimedOut() }
        return reading
    }
}

@Suite("Quick add with a model")
struct SmartQuickAddParserTests {
    private let context = QuickAddContext(candidateNames: ["Sam Carter", "Priya Shah"], defaultCurrencyCode: "USD")
    private let note = "dinner 60 with Sam and Priya, I paid, Priya owes 10 less"

    private func parser(_ reader: (any QuickAddReader)?) -> SmartQuickAddParser {
        SmartQuickAddParser(reader: reader, categories: StubSuggester(result: nil))
    }

    @Test func validReadingIsUsed() async {
        var reading = QuickAddReading()
        reading.title = "dinner"
        reading.amount = "60"
        reading.participants = ["Sam", "Priya"]
        reading.payer = "me"
        reading.split = .adjustments
        reading.adjustments = [.init(name: "Priya", amount: "10", isLess: true)]
        let draft = await parser(StubReader(reading: reading)).parse(note, context: context)
        #expect(draft.source == .model)
        #expect(draft.amount == Money(minorUnits: 6000, currencyCode: "USD"))
        #expect(draft.title == "Dinner")
        #expect(draft.participantNames == ["Sam Carter", "Priya Shah"])
        #expect(draft.payer == .me)
        #expect(draft.splitHint == .adjustments([
            QuickAddShare(name: "Priya Shah", amount: Money(minorUnits: -1000, currencyCode: "USD"))
        ]))
    }

    @Test func inventedFieldsFallBackToTheRules() async {
        var reading = QuickAddReading()
        reading.title = "fancy steakhouse"
        reading.amount = "75"
        reading.participants = ["Zed"]
        reading.payer = "Mallory"
        let draft = await parser(StubReader(reading: reading)).parse(note, context: context)
        #expect(draft.amount?.minorUnits == 6000)
        #expect(draft.title == "Dinner")
        #expect(Set(draft.participantNames) == ["Sam Carter", "Priya Shah"])
        #expect(draft.payer == .me)
        #expect(draft.source == .rules)
    }

    @Test func throwingOrUnavailableModelsAreSilent() async {
        let rules = RuleBasedQuickAddParser().parseNow(note, context: context)
        let thrown = await parser(StubReader(reading: nil)).parse(note, context: context)
        #expect(thrown == rules)
        let unavailable = await parser(StubReader(isAvailable: false, reading: QuickAddReading())).parse(note, context: context)
        #expect(unavailable == rules)
        let none = await parser(nil).parse(note, context: context)
        #expect(none == rules)
    }

    @Test func categoryFallsBackToTheSuggester() async {
        let suggester = StubSuggester(result: .init(category: .gifts, source: .model))
        let smart = SmartQuickAddParser(reader: nil, categories: suggester)
        let draft = await smart.parse("zorblax 20", context: context)
        #expect(draft.category == .gifts)
    }

    @Test func amountMustBeWrittenInTheNote() {
        var reading = QuickAddReading()
        reading.amount = "75"
        #expect(QuickAddValidator.validate(reading, text: note, context: context).amount == nil)
        reading.amount = "$60.00"
        #expect(QuickAddValidator.validate(reading, text: note, context: context).amount?.minorUnits == 6000)
        reading.amount = "-60"
        #expect(QuickAddValidator.validate(reading, text: note, context: context).amount == nil)
    }

    @Test func amountsWrittenWithAKSuffixCount() {
        var reading = QuickAddReading()
        reading.amount = "1500"
        #expect(QuickAddValidator.validate(reading, text: "trip 1.5k", context: context).amount?.minorUnits == 150_000)
    }

    @Test func currencyNeedsEvidenceInTheNote() {
        var reading = QuickAddReading()
        reading.currency = "EUR"
        #expect(QuickAddValidator.validate(reading, text: "dinner 60", context: context).currencyHint == nil)
        #expect(QuickAddValidator.validate(reading, text: "dinner 60 euros", context: context).currencyHint == "EUR")
    }

    @Test func namesMustBeMembersOrWrittenInTheNote() {
        var reading = QuickAddReading()
        reading.participants = ["Sam", "sam", "Priya Shah", "Nobody", "me", "I"]
        let draft = QuickAddValidator.validate(reading, text: "dinner with Sam and Priya", context: context)
        #expect(draft.participantNames == ["Sam Carter", "Priya Shah"])
        reading.participants = ["jordan"]
        let fresh = QuickAddValidator.validate(reading, text: "dinner with Jordan", context: context)
        #expect(fresh.participantNames == ["Jordan"])
    }

    @Test func payerMeNeedsPayWords() {
        var reading = QuickAddReading()
        reading.payer = "me"
        #expect(QuickAddValidator.validate(reading, text: "dinner 60", context: context).payer == nil)
        #expect(QuickAddValidator.validate(reading, text: "I paid for dinner 60", context: context).payer == .me)
    }

    @Test func equalSplitNeedsWordsInTheNote() {
        var reading = QuickAddReading()
        reading.split = .equal
        #expect(QuickAddValidator.validate(reading, text: "dinner 60 with Sam", context: context).splitHint == nil)
        #expect(QuickAddValidator.validate(reading, text: "dinner 60 with Sam split evenly", context: context).splitHint == .equal)
    }

    @Test func spelledTitleMustUseTheWritersWords() {
        var reading = QuickAddReading()
        reading.title = "Romantic candlelit dinner"
        #expect(QuickAddValidator.validate(reading, text: "dinner 60", context: context).title.isEmpty)
        reading.title = "dinner"
        #expect(QuickAddValidator.validate(reading, text: "dinner 60", context: context).title == "Dinner")
    }

    @Test func aSpacedThousandIsOneWrittenAmount() {
        #expect(QuickAddValidator.writtenAmounts(in: "dinner 1 234,50", currencyCode: "USD") == [123_450])
        #expect(QuickAddValidator.writtenAmounts(in: "table 12 45", currencyCode: "USD") == [1200, 4500])
        #expect(QuickAddValidator.writtenAmounts(in: "tickets 2 500", currencyCode: "USD") == [200, 50_000])
    }

    @Test func aModelCannotOverrideThePayerTheRulesRead() async {
        var reading = QuickAddReading()
        reading.payer = "me"
        let named = await parser(StubReader(reading: reading)).parse("Sam paid 60 for dinner with Priya", context: context)
        #expect(named.payer == .person("Sam Carter"))
        #expect(QuickAddValidator.validate(reading, text: "Sam paid 60 for dinner with Priya", context: context).payer == nil)

        reading.payer = "Sam"
        let mine = await parser(StubReader(reading: reading)).parse("dinner 60 with Sam, I paid", context: context)
        #expect(mine.payer == .me)
        #expect(QuickAddValidator.validate(reading, text: "dinner 60 with Sam, I paid", context: context).payer == nil)
    }

    @Test func aModelCannotFlipAnAdjustment() async {
        var reading = QuickAddReading()
        reading.split = .adjustments
        reading.adjustments = [.init(name: "Priya", amount: "10", isLess: true)]
        let more = QuickAddSplitHint.adjustments([
            QuickAddShare(name: "Priya Shah", amount: Money(minorUnits: 1000, currencyCode: "USD"))
        ])
        let draft = await parser(StubReader(reading: reading)).parse("Priya owes 10 more", context: context)
        #expect(draft.splitHint == more)
        #expect(QuickAddValidator.validate(reading, text: "Priya owes 10 more", context: context).splitHint == nil)

        // both words are written, so only the rules can tell whose is whose
        let both = await parser(StubReader(reading: reading)).parse("dinner 60, Priya owes 10 more, Sam owes 5 less", context: context)
        #expect(both.splitHint == .adjustments([
            QuickAddShare(name: "Priya Shah", amount: Money(minorUnits: 1000, currencyCode: "USD")),
            QuickAddShare(name: "Sam Carter", amount: Money(minorUnits: -500, currencyCode: "USD"))
        ]))
    }

    @Test func aModelFillsInAPayerOrDirectionTheRulesMissed() async {
        var reading = QuickAddReading()
        reading.payer = "Sam"
        let named = await parser(StubReader(reading: reading)).parse("Sam has paid 60 for dinner", context: context)
        #expect(named.payer == .person("Sam Carter"))

        reading.payer = "me"
        let mine = await parser(StubReader(reading: reading)).parse("dinner 60 with Sam, I already paid", context: context)
        #expect(mine.payer == .me)

        reading = QuickAddReading()
        reading.split = .adjustments
        reading.adjustments = [.init(name: "Priya", amount: "10", isLess: true)]
        let less = await parser(StubReader(reading: reading)).parse("dinner 60 with Priya who should get 10 less", context: context)
        #expect(less.splitHint == .adjustments([
            QuickAddShare(name: "Priya Shah", amount: Money(minorUnits: -1000, currencyCode: "USD"))
        ]))
    }
}
