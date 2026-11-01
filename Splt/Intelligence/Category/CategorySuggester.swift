import Foundation
import NaturalLanguage

/// A suggested category and how it was found. Callers show it as a tap to accept, never apply it silently.
struct CategorySuggestion: Equatable, Sendable {
    enum Source: Sendable {
        case keyword
        case model
        case embedding
    }

    var category: ExpenseCategoryHint
    var source: Source
}

/// Suggests a category from what an expense is called and where it was paid.
protocol CategorySuggesting: Sendable {
    func suggest(title: String, merchant: String?) async -> CategorySuggestion?
}

/// Looks the words up in the fixed table. Deterministic and instant.
struct KeywordCategorySuggester: CategorySuggesting {
    var table: KeywordCategoryTable = .standard

    func suggest(title: String, merchant: String?) async -> CategorySuggestion? {
        suggestNow(title: title, merchant: merchant)
    }

    func suggestNow(title: String, merchant: String?) -> CategorySuggestion? {
        table.category(for: [merchant, title]).map { CategorySuggestion(category: $0, source: .keyword) }
    }
}

/// Compares each word with a few anchor words per category using the system word embedding.
/// Handles words the table does not know ("bruschetta") without any model download.
struct EmbeddingCategorySuggester: CategorySuggesting {
    /// Cosine distance between two words, or nil when either has no vector.
    typealias Distance = @Sendable (String, String) -> Double?

    var maximumDistance: Double = 0.85
    var distance: Distance = EmbeddingCategorySuggester.systemDistance

    private static let anchors: [ExpenseCategoryHint: [String]] = [
        .food: ["food", "meal", "restaurant", "eat"],
        .groceries: ["groceries", "supermarket", "vegetables"],
        .drinks: ["drink", "beer", "coffee", "cocktail"],
        .transport: ["taxi", "transport", "fuel", "parking"],
        .travel: ["flight", "travel", "airport", "vacation"],
        .lodging: ["hotel", "lodging", "hostel"],
        .entertainment: ["movie", "concert", "entertainment", "game"],
        .shopping: ["shopping", "clothes", "store"],
        .utilities: ["electricity", "internet", "utility", "phone"],
        .rent: ["rent", "mortgage", "apartment"],
        .health: ["doctor", "medicine", "health", "gym"],
        .gifts: ["gift", "present", "flowers"]
    ]

    func suggest(title: String, merchant: String?) async -> CategorySuggestion? {
        suggestNow(title: title, merchant: merchant)
    }

    func suggestNow(title: String, merchant: String?) -> CategorySuggestion? {
        let words = [merchant, title].compactMap { $0 }.flatMap(\.foldedWords).filter { $0.count >= 3 }
        var best: (category: ExpenseCategoryHint, distance: Double)?
        for word in words {
            for (category, anchorWords) in Self.anchors {
                for anchor in anchorWords {
                    guard let value = distance(word, anchor), value <= maximumDistance else { continue }
                    if best == nil || value < best!.distance {
                        best = (category, value)
                    }
                }
            }
        }
        return best.map { CategorySuggestion(category: $0.category, source: .embedding) }
    }

    static let systemDistance: Distance = { first, second in
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        let value = embedding.distance(between: first, and: second, distanceType: .cosine)
        return value.isFinite && value <= 2 ? value : nil
    }
}

/// Asks the on-device language model to pick one category from the fixed list.
struct ModelCategorySuggester: CategorySuggesting {
    func suggest(title: String, merchant: String?) async -> CategorySuggestion? {
        guard OnDeviceModel.isAvailable else { return nil }
        let text = [merchant, title].compactMap { $0 }.joined(separator: " - ").tidied
        guard text.contains(where: \.isLetter), text.count <= 120 else { return nil }

        let choices = ExpenseCategoryHint.allCases.map(\.rawValue)
        let list = ExpenseCategoryHint.allCases
            .map { "\($0.rawValue): \($0.promptDescription)" }
            .joined(separator: "\n")
        let answer = try? await OnDeviceModel.choose(
            from: choices,
            instructions: """
                You file shared expenses into one category. The note may be in any language. \
                Categories:
                \(list)
                Answer with the single best category. Use other when nothing fits.
                """,
            prompt: "Expense: \(text)"
        )
        guard let answer, let category = ExpenseCategoryHint(rawValue: answer) else { return nil }
        return CategorySuggestion(category: category, source: .model)
    }
}

/// Tries the keyword table first, then the language model when it is available, then the
/// word embedding. Returns nil, never an error, when none of them has an opinion.
struct CategorySuggester: CategorySuggesting {
    var keyword: any CategorySuggesting = KeywordCategorySuggester()
    var model: (any CategorySuggesting)? = ModelCategorySuggester()
    var embedding: any CategorySuggesting = EmbeddingCategorySuggester()

    func suggest(title: String, merchant: String?) async -> CategorySuggestion? {
        let cleanTitle = title.tidied
        let cleanMerchant = merchant?.tidied.nilIfEmpty
        guard !cleanTitle.isEmpty || cleanMerchant != nil else { return nil }

        if let hit = await keyword.suggest(title: cleanTitle, merchant: cleanMerchant) { return hit }
        if let model, let hit = await model.suggest(title: cleanTitle, merchant: cleanMerchant) { return hit }
        return await embedding.suggest(title: cleanTitle, merchant: cleanMerchant)
    }
}

fileprivate extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
