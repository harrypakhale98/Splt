import Testing
@testable import Splt

@Suite("Category suggestions")
struct CategorySuggesterTests {
    private let table = KeywordCategoryTable.standard

    @Test(arguments: [
        ("Dinner at the Thai place", ExpenseCategoryHint.food),
        ("Uber to airport", .transport),
        ("Weekly groceries", .groceries),
        ("Coffee", .drinks),
        ("Hotel Lisbon", .lodging),
        ("Electricity bills", .utilities),
        ("Movie night", .entertainment),
        ("Birthday flowers", .gifts),
        ("Rent for March", .rent)
    ])
    func keywordTableFindsTheCategory(title: String, expected: ExpenseCategoryHint) {
        #expect(table.category(for: [title]) == expected)
    }

    @Test func unknownWordsGiveNoKeywordHit() {
        #expect(table.category(for: ["zzzz qqqq"]) == nil)
    }

    @Test func merchantCountsAlongsideTitle() {
        #expect(table.category(for: ["Weekend", "Starbucks"]) == .drinks)
    }

    @Test func pluralsAndPhrasesMatch() {
        #expect(table.category(for: ["Pizzas"]) == .food)
        #expect(table.category(for: ["Phone bill"]) == .utilities)
    }

    @Test func recognisesExpenseWordsSoTheyAreNotTakenForNames() {
        #expect(table.recognises(word: "Pizza"))
        #expect(!table.recognises(word: "Priya"))
    }

    @Test func embeddingSuggesterUsesTheNearestAnchor() async {
        let suggester = EmbeddingCategorySuggester(maximumDistance: 0.5) { word, anchor in
            word == "bruschetta" && anchor == "meal" ? 0.3 : 1.2
        }
        let result = await suggester.suggest(title: "Bruschetta", merchant: nil)
        #expect(result == CategorySuggestion(category: .food, source: .embedding))
    }

    @Test func embeddingSuggesterStaysQuietWhenNothingIsClose() async {
        let suggester = EmbeddingCategorySuggester(maximumDistance: 0.5) { _, _ in 1.4 }
        #expect(await suggester.suggest(title: "Bruschetta", merchant: nil) == nil)
        let noVectors = EmbeddingCategorySuggester { _, _ in nil }
        #expect(await noVectors.suggest(title: "Bruschetta", merchant: nil) == nil)
    }

    @Test func compositeStopsAtTheKeywordHit() async {
        let suggester = CategorySuggester(
            keyword: KeywordCategorySuggester(),
            model: StubSuggester(result: .init(category: .gifts, source: .model)),
            embedding: StubSuggester(result: nil)
        )
        let result = await suggester.suggest(title: "Pizza", merchant: nil)
        #expect(result == CategorySuggestion(category: .food, source: .keyword))
    }

    @Test func compositeFallsThroughModelThenEmbedding() async {
        let embedded = CategorySuggestion(category: .health, source: .embedding)
        let withModel = CategorySuggester(
            keyword: KeywordCategorySuggester(),
            model: StubSuggester(result: .init(category: .gifts, source: .model)),
            embedding: StubSuggester(result: embedded)
        )
        #expect(await withModel.suggest(title: "Qwxz", merchant: nil)?.category == .gifts)

        let withoutModel = CategorySuggester(
            keyword: KeywordCategorySuggester(),
            model: StubSuggester(result: nil),
            embedding: StubSuggester(result: embedded)
        )
        #expect(await withoutModel.suggest(title: "Qwxz", merchant: nil) == embedded)
    }

    @Test func emptyInputGivesNothing() async {
        let suggester = CategorySuggester(
            keyword: KeywordCategorySuggester(),
            model: nil,
            embedding: StubSuggester(result: .init(category: .food, source: .embedding))
        )
        #expect(await suggester.suggest(title: "  ", merchant: nil) == nil)
    }

    @Test func categoriesHaveSymbolsAndNames() {
        for category in ExpenseCategoryHint.allCases {
            #expect(!category.displayName.isEmpty)
            #expect(!category.symbolName.isEmpty)
        }
    }
}

struct StubSuggester: CategorySuggesting {
    var result: CategorySuggestion?

    func suggest(title: String, merchant: String?) async -> CategorySuggestion? {
        result
    }
}
