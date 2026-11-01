import Foundation

/// Suggests a symbol from the words in a group name. Plain keyword matching, so it works offline and instantly.
enum GroupSymbolSuggester {
    private static let table: [(symbol: String, words: Set<String>)] = [
        ("airplane", ["trip", "flight", "vacation", "holiday", "travel", "abroad"]),
        ("beach.umbrella.fill", ["beach", "island", "summer", "cruise"]),
        ("tent.fill", ["camp", "camping", "hike", "hiking", "trek"]),
        ("figure.skiing.downhill", ["ski", "skiing", "snowboard"]),
        ("house.fill", ["flat", "apartment", "house", "home", "rent", "roommate", "housemate", "household"]),
        ("heart.fill", ["couple", "partner", "wedding", "honeymoon", "anniversary", "date"]),
        ("fork.knife", ["dinner", "lunch", "brunch", "food", "restaurant", "meal"]),
        ("cart.fill", ["grocery", "groceries", "shopping", "market"]),
        ("car.fill", ["road", "roadtrip", "car", "carpool", "drive"]),
        ("gift.fill", ["gift", "birthday", "present", "party"]),
        ("film.fill", ["movie", "cinema", "film"]),
        ("music.note", ["concert", "festival", "music", "gig"]),
        ("sportscourt.fill", ["football", "soccer", "basketball", "tennis", "padel", "sport"]),
        ("wineglass.fill", ["wine", "drink", "bar", "pub", "cocktail"]),
        ("briefcase.fill", ["work", "office", "team", "business", "conference"]),
        ("graduationcap.fill", ["school", "uni", "college", "class", "study"]),
        ("pawprint.fill", ["pet", "dog", "cat", "vet"])
    ]

    /// A symbol for the first matching word, or nil when nothing fits.
    static func symbol(for name: String) -> String? {
        let words = name.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map { singular(String($0)) }
        for word in words {
            if let match = table.first(where: { $0.words.contains(word) }) {
                return match.symbol
            }
        }
        return nil
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }
}
