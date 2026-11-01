import Foundation
import SpltCore

/// Everyday words that point at an expense category, and the other small words of a question.
enum SearchVocabulary {
    static let categoryWords: [String: ExpenseCategory] = {
        let table: [ExpenseCategory: [String]] = [
            .dining: ["dinner", "lunch", "breakfast", "brunch", "restaurant", "food", "meal", "dining", "takeout"],
            .drinks: ["drink", "drinks", "bar", "beer", "wine", "coffee", "cocktail"],
            .groceries: ["grocery", "groceries", "supermarket"],
            .transport: ["transport", "taxi", "cab", "uber", "train", "bus", "metro", "ride"],
            .fuel: ["fuel", "gas", "petrol"],
            .travel: ["travel", "flight", "flights"],
            .lodging: ["hotel", "airbnb", "lodging", "stay", "hostel"],
            .entertainment: ["movie", "movies", "concert", "entertainment", "show", "tickets", "ticket"],
            .utilities: ["utility", "utilities", "electricity", "internet", "wifi", "water", "bill", "bills"],
            .rent: ["rent"],
            .home: ["furniture", "home"],
            .shopping: ["shopping", "clothes"],
            .health: ["health", "pharmacy", "doctor"],
            .gifts: ["gift", "gifts", "present"],
            .subscriptions: ["subscription", "subscriptions"],
            .pets: ["pet", "pets", "vet"]
        ]
        var words: [String: ExpenseCategory] = [:]
        for (category, entries) in table {
            for entry in entries { words[entry] = category }
        }
        return words
    }()

    /// Words that carry no meaning for the search.
    static let stopWords: Set<String> = [
        "the", "a", "an", "in", "on", "of", "for", "by", "with", "and", "from", "to", "my", "our", "all",
        "show", "find", "me", "expenses", "expense", "spent", "paid", "pays", "that", "what", "which",
        "were", "was", "is", "are", "at", "during", "any", "every", "i", "list", "get", "give", "between"
    ]

    static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12
    ]

    static let payerVerbs: Set<String> = ["paid", "pays", "covered", "bought", "treated"]
}
