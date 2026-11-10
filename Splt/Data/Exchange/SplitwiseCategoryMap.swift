import SpltCore

/// Maps the category names Splitwise exports onto Splt's categories.
enum SplitwiseCategoryMap {
    private static let rules: [(keywords: [String], category: ExpenseCategory)] = [
        (["grocer"], .groceries),
        (["liquor", "bar", "drink"], .drinks),
        (["dining", "restaurant", "food", "coffee", "lunch", "dinner"], .dining),
        (["gas/fuel", "fuel", "petrol"], .fuel),
        (["taxi", "bus", "train", "transport", "car", "parking", "bicycle", "uber"], .transport),
        (["plane", "flight", "travel", "trip"], .travel),
        (["hotel", "lodging", "accommodation"], .lodging),
        (["rent", "mortgage"], .rent),
        (["electric", "heat", "water", "phone", "internet", "utilit", "trash"], .utilities),
        (["entertainment", "movie", "music", "game", "sport"], .entertainment),
        (["household", "furniture", "cleaning", "maintenance", "home"], .home),
        (["pet"], .pets),
        (["medical", "health"], .health),
        (["gift"], .gifts),
        (["cloth", "shopping"], .shopping),
        (["education", "school"], .education),
        (["subscription"], .subscriptions)
    ]

    static func category(for name: String) -> ExpenseCategory {
        let lowered = name.lowercased()
        if let exact = ExpenseCategory(rawValue: lowered) { return exact }
        let words = lowered.split { !$0.isLetter }
        for rule in rules where rule.keywords.contains(where: { keyword in words.contains { $0.hasPrefix(keyword) } }) {
            return rule.category
        }
        return .general
    }
}
