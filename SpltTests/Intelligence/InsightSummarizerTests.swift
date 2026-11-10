import Testing
@testable import Splt

private struct StubWriter: InsightWriting {
    var text: String?

    func write(facts: String) async throws -> String {
        guard let text else { throw OnDeviceModel.TimedOut() }
        return text
    }
}

private let trip = InsightInput(
    groupName: "Lisbon",
    kind: .trip,
    expenseCount: 12,
    categories: [
        .init(name: "Food", minorUnits: 60_000),
        .init(name: "Transport", minorUnits: 20_000),
        .init(name: "Stay", minorUnits: 20_000)
    ],
    members: [
        .init(name: "Sam", paidMinorUnits: 70_000),
        .init(name: "Priya", paidMinorUnits: 20_000),
        .init(name: "Alex", paidMinorUnits: 10_000)
    ]
)

@Suite("Insights")
struct InsightSummarizerTests {
    @Test func templateNamesTheBiggestCategoryAndPayer() {
        #expect(InsightSummarizer.template(for: trip) == "Most of the money on this trip went on food. Sam covered most of it.")
    }

    @Test func categoriesReadAsWhatTheMoneyWentOn() {
        #expect(InsightSummarizer.spentOn("Stay") == "places to stay")
        #expect(InsightSummarizer.spentOn("Transport") == "getting around")
        #expect(InsightSummarizer.spentOn("Groceries") == "groceries")
    }

    @Test func templateHandlesSpreadSpendingAndEvenPayers() {
        let spread = InsightInput(
            groupName: "Flat",
            kind: .household,
            expenseCount: 4,
            categories: [.init(name: "Rent", minorUnits: 30), .init(name: "Bills", minorUnits: 29), .init(name: "Food", minorUnits: 28)],
            members: [.init(name: "Sam", paidMinorUnits: 50), .init(name: "Priya", paidMinorUnits: 48)]
        )
        #expect(InsightSummarizer.template(for: spread) == "Rent was the biggest part of your shared spending. Everyone has paid a similar amount.")
    }

    @Test func templateFallsBackToACount() {
        #expect(InsightSummarizer.template(for: InsightInput(groupName: "G", expenseCount: 1, categories: [])) == "One expense so far.")
        #expect(InsightSummarizer.template(for: InsightInput(groupName: "G", expenseCount: 3, categories: [])) == "3 expenses so far.")
    }

    @Test func nothingToSayWithoutExpenses() async {
        let empty = InsightInput(groupName: "G", expenseCount: 0, categories: [])
        #expect(await InsightSummarizer(writer: nil).summarize(empty) == nil)
    }

    @Test func modelTextIsUsedWhenItPassesTheChecks() async {
        let summarizer = InsightSummarizer(writer: StubWriter(text: "Most of the Lisbon trip went to food, and Sam picked up most bills"))
        #expect(await summarizer.summarize(trip) == "Most of the Lisbon trip went to food, and Sam picked up most bills.")
    }

    @Test(arguments: [
        "Most of this trip went to food, about 60 percent.",
        "You spent $600 on food.",
        "Sam spent a lot. Priya did too. Alex did not.",
        "Most of it went to food with Jordan.",
        "- food",
        ""
    ])
    func badModelTextFallsBackToTheTemplate(text: String) async {
        let summarizer = InsightSummarizer(writer: StubWriter(text: text))
        #expect(await summarizer.summarize(trip) == InsightSummarizer.template(for: trip))
    }

    @Test func unavailableModelFallsBackToTheTemplate() async {
        let summarizer = InsightSummarizer(writer: StubWriter(text: nil))
        #expect(await summarizer.summarize(trip) == InsightSummarizer.template(for: trip))
    }

    @Test func factsListShareOfSpendingAsWholePercents() {
        let facts = InsightSummarizer.facts(for: trip)
        #expect(facts.contains("Category Food: 60 percent of spending"))
        #expect(facts.contains("Sam paid 70 percent of the bills"))
        #expect(facts.contains("Expenses logged: 12"))
    }

    @Test func percentUsesIntegerRounding() {
        #expect(InsightSummarizer.percent(1, of: 3) == 33)
        #expect(InsightSummarizer.percent(2, of: 3) == 67)
        #expect(InsightSummarizer.percent(5, of: 0) == 0)
    }

    @Test func hugeStoredAmountsNeitherOverflowNorBreakThePercent() {
        let input = InsightInput(
            groupName: "Trip", kind: .trip, expenseCount: 3,
            categories: [
                InsightInput.CategoryAmount(name: "Food", minorUnits: .max),
                InsightInput.CategoryAmount(name: "Taxi", minorUnits: .max)
            ],
            members: [
                InsightInput.MemberAmount(name: "Sam", paidMinorUnits: .max),
                InsightInput.MemberAmount(name: "Ana", paidMinorUnits: .max)
            ]
        )
        #expect(input.totalByCategory == .max)
        #expect(input.totalPaid == .max)
        #expect(InsightSummarizer.percent(.max, of: 1) == Int.max)
    }

    @Test func membersWhoPaidNothingDoNotChangeTheOtherSentences() {
        let quiet = [InsightInput.MemberAmount(name: "Alex", paidMinorUnits: 0), InsightInput.MemberAmount(name: "Jo", paidMinorUnits: 0)]
        let food = [InsightInput.CategoryAmount(name: "Food", minorUnits: 100)]
        let split = InsightInput(
            groupName: "Flat", expenseCount: 2, categories: food,
            members: [.init(name: "Sam", paidMinorUnits: 50), .init(name: "Priya", paidMinorUnits: 50)] + quiet
        )
        #expect(InsightSummarizer.template(for: split) == "Most of this group's spending went on food.")

        let lead = InsightInput(
            groupName: "Flat", expenseCount: 2, categories: food,
            members: [.init(name: "Sam", paidMinorUnits: 100)] + quiet
        )
        #expect(InsightSummarizer.template(for: lead) == "Most of this group's spending went on food. Sam covered most of it.")
        let facts = InsightSummarizer.facts(for: lead)
        #expect(facts.contains("Sam paid 100 percent of the bills"))
        #expect(!facts.contains("Alex"))
    }
}
