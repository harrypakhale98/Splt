import Foundation

/// A broad kind of spending. A hint only: the app maps it onto its own categories.
enum ExpenseCategoryHint: String, CaseIterable, Codable, Sendable {
    case food
    case groceries
    case drinks
    case transport
    case travel
    case lodging
    case entertainment
    case shopping
    case utilities
    case rent
    case health
    case gifts
    case other

    var displayName: String {
        switch self {
        case .food: "Food"
        case .groceries: "Groceries"
        case .drinks: "Drinks"
        case .transport: "Transport"
        case .travel: "Travel"
        case .lodging: "Stay"
        case .entertainment: "Fun"
        case .shopping: "Shopping"
        case .utilities: "Bills"
        case .rent: "Rent"
        case .health: "Health"
        case .gifts: "Gifts"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .groceries: "cart"
        case .drinks: "cup.and.saucer"
        case .transport: "car"
        case .travel: "airplane"
        case .lodging: "bed.double"
        case .entertainment: "ticket"
        case .shopping: "bag"
        case .utilities: "bolt"
        case .rent: "house"
        case .health: "cross.case"
        case .gifts: "gift"
        case .other: "ellipsis.circle"
        }
    }

    /// One plain phrase per category for prompts and embedding anchors.
    var promptDescription: String {
        switch self {
        case .food: "restaurants, takeout, meals, snacks"
        case .groceries: "supermarket and household food shopping"
        case .drinks: "coffee, bars, beer, wine, cocktails"
        case .transport: "taxi, ride share, fuel, parking, public transport"
        case .travel: "flights, trains, tours, visas, luggage"
        case .lodging: "hotels, hostels, vacation rentals"
        case .entertainment: "movies, concerts, games, events, subscriptions"
        case .shopping: "clothes, electronics, general purchases"
        case .utilities: "electricity, water, internet, phone, gas bills"
        case .rent: "rent, mortgage, home maintenance"
        case .health: "doctor, pharmacy, gym, wellness"
        case .gifts: "presents, flowers, donations"
        case .other: "anything else"
        }
    }
}
