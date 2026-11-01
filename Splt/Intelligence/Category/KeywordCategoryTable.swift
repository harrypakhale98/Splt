import Foundation

/// A fixed word list that maps everyday expense words and well known merchants to a category.
/// Fast, private and predictable, so it is tried before anything smarter.
struct KeywordCategoryTable: Sendable {
    static let standard = KeywordCategoryTable()

    private let words: [String: ExpenseCategoryHint]
    private let phrases: [(phrase: String, category: ExpenseCategoryHint)]

    init() {
        var words: [String: ExpenseCategoryHint] = [:]
        var phrases: [(String, ExpenseCategoryHint)] = []
        for (category, entries) in Self.entries {
            for entry in entries {
                if entry.contains(" ") {
                    phrases.append((entry, category))
                } else {
                    words[entry] = category
                }
            }
        }
        self.words = words
        self.phrases = phrases
    }

    /// True when the word alone is a recognised expense word. Used to avoid reading "pizza" as a name.
    func recognises(word: String) -> Bool {
        lookup(word.folded) != nil
    }

    /// The best category for the given texts, or nil when nothing matches.
    func category(for texts: [String?]) -> ExpenseCategoryHint? {
        var scores: [ExpenseCategoryHint: Int] = [:]
        var firstSeen: [ExpenseCategoryHint: Int] = [:]
        var position = 0
        for text in texts.compactMap({ $0 }) {
            let folded = text.foldedWords
            let joined = " " + folded.joined(separator: " ") + " "
            for (phrase, category) in phrases where joined.contains(" \(phrase) ") {
                scores[category, default: 0] += 2
                firstSeen[category] = firstSeen[category] ?? position
                position += 1
            }
            for word in folded {
                guard let category = lookup(word) else { continue }
                scores[category, default: 0] += 1
                firstSeen[category] = firstSeen[category] ?? position
                position += 1
            }
        }
        return scores.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (firstSeen[lhs.key] ?? 0) > (firstSeen[rhs.key] ?? 0)
        }?.key
    }

    private func lookup(_ word: String) -> ExpenseCategoryHint? {
        if let hit = words[word] { return hit }
        if word.hasSuffix("es"), let hit = words[String(word.dropLast(2))] { return hit }
        if word.hasSuffix("s"), let hit = words[String(word.dropLast())] { return hit }
        return nil
    }

    private static let entries: [(ExpenseCategoryHint, [String])] = [
        (.food, [
            "dinner", "lunch", "breakfast", "brunch", "meal", "restaurant", "takeout", "takeaway", "pizza",
            "burger", "sushi", "taco", "ramen", "noodle", "curry", "kebab", "sandwich", "snack", "dessert",
            "bbq", "buffet", "diner", "bistro", "cafe", "bakery", "delivery", "food", "eat", "feast",
            "mcdonalds", "kfc", "subway", "chipotle", "dominos", "doordash", "ubereats", "deliveroo",
            "zomato", "swiggy", "grubhub", "just eat", "pizza hut", "burger king", "taco bell", "wendys",
            "popeyes", "nandos", "ice cream", "biryani", "dosa", "thali", "pasta", "steak", "tapas"
        ]),
        (.groceries, [
            "groceries", "grocery", "supermarket", "market", "produce", "costco", "walmart", "tesco",
            "aldi", "lidl", "kroger", "safeway", "trader joes", "whole foods", "sainsburys", "asda",
            "waitrose", "carrefour", "bigbasket", "blinkit", "instacart", "milk", "bread", "eggs",
            "vegetables", "fruit", "toiletries", "household", "supplies", "target", "ikea"
        ]),
        (.drinks, [
            "coffee", "tea", "latte", "espresso", "starbucks", "costa", "dunkin", "beer", "beers", "wine",
            "cocktail", "cocktails", "drinks", "drink", "bar", "pub", "brewery", "whiskey", "vodka", "booze",
            "smoothie", "juice", "boba", "happy hour", "shots", "champagne", "liquor"
        ]),
        (.transport, [
            "uber", "lyft", "taxi", "cab", "rideshare", "ride", "bus", "metro",
            "subway fare", "train fare", "tram", "fuel", "gas", "petrol", "diesel", "parking", "toll",
            "tolls", "fare", "commute", "scooter", "rickshaw", "car wash", "charging", "ev charging"
        ]),
        (.travel, [
            "flight", "flights", "airline", "airfare", "airport", "train", "tickets", "ticket", "visa",
            "passport", "luggage", "baggage", "trip", "tour", "excursion", "cruise", "ferry", "rental car",
            "car rental", "hertz", "avis", "expedia", "skyscanner", "ryanair", "easyjet", "emirates", "souvenir", "souvenirs", "travel", "insurance"
        ]),
        (.lodging, [
            "hotel", "hostel", "airbnb", "booking", "motel", "resort", "lodge", "lodging", "accommodation",
            "villa", "cabin", "guesthouse", "stay", "night stay", "marriott", "hilton", "hyatt"
        ]),
        (.entertainment, [
            "movie", "movies", "cinema", "film", "concert", "show", "theatre", "theater", "museum",
            "gallery", "club", "nightclub", "festival", "game", "games", "bowling", "arcade", "karaoke",
            "netflix", "spotify", "hulu", "disney", "youtube", "playstation", "xbox", "steam", "nintendo",
            "amc", "stadium", "amusement", "zoo", "escape room", "mini golf", "subscription"
        ]),
        (.shopping, [
            "clothes", "clothing", "shirt", "shoes", "sneakers", "jacket", "dress", "jeans", "mall",
            "amazon", "ebay", "etsy", "zara", "nike", "adidas", "electronics", "phone case",
            "laptop", "headphones", "furniture", "decor", "shopping", "flipkart", "myntra", "book", "books"
        ]),
        (.utilities, [
            "electricity", "electric", "water", "internet", "wifi", "broadband", "phone bill", "mobile",
            "utilities", "utility", "heating", "trash", "sewer", "cable", "bills", "recharge",
            "comcast", "verizon", "vodafone", "airtel", "jio", "tmobile", "laundry", "cleaning"
        ]),
        (.rent, [
            "rent", "mortgage", "landlord", "lease", "deposit", "maintenance", "repair", "repairs",
            "plumber", "electrician", "hoa", "society", "furnishing"
        ]),
        (.health, [
            "doctor", "pharmacy", "medicine", "medical", "dentist", "hospital", "clinic", "prescription",
            "gym", "yoga", "pilates", "therapy", "massage", "spa", "salon", "haircut", "cvs", "walgreens",
            "vitamins", "optician", "glasses", "checkup", "physio"
        ]),
        (.gifts, [
            "gift", "gifts", "present", "presents", "flowers", "bouquet", "birthday", "wedding", "donation",
            "charity", "anniversary", "baby shower"
        ])
    ]
}
