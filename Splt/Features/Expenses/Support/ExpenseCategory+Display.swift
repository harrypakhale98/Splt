import Foundation
import SpltCore

extension ExpenseCategory {
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .groceries: String(localized: "Groceries")
        case .dining: String(localized: "Dining")
        case .drinks: String(localized: "Drinks")
        case .transport: String(localized: "Transport")
        case .fuel: String(localized: "Fuel")
        case .travel: String(localized: "Travel")
        case .lodging: String(localized: "Stay")
        case .entertainment: String(localized: "Entertainment")
        case .utilities: String(localized: "Utilities")
        case .rent: String(localized: "Rent")
        case .home: String(localized: "Home")
        case .shopping: String(localized: "Shopping")
        case .health: String(localized: "Health")
        case .gifts: String(localized: "Gifts")
        case .education: String(localized: "Education")
        case .subscriptions: String(localized: "Subscriptions")
        case .pets: String(localized: "Pets")
        case .other: String(localized: "Other")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "tag"
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .drinks: "cup.and.saucer"
        case .transport: "car"
        case .fuel: "fuelpump"
        case .travel: "airplane"
        case .lodging: "bed.double"
        case .entertainment: "ticket"
        case .utilities: "bolt"
        case .rent: "house"
        case .home: "sofa"
        case .shopping: "bag"
        case .health: "cross.case"
        case .gifts: "gift"
        case .education: "graduationcap"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .pets: "pawprint"
        case .other: "ellipsis.circle"
        }
    }

    /// The closest category for a suggestion from the on-device category suggester.
    init(_ hint: ExpenseCategoryHint) {
        switch hint {
        case .food: self = .dining
        case .groceries: self = .groceries
        case .drinks: self = .drinks
        case .transport: self = .transport
        case .travel: self = .travel
        case .lodging: self = .lodging
        case .entertainment: self = .entertainment
        case .shopping: self = .shopping
        case .utilities: self = .utilities
        case .rent: self = .rent
        case .health: self = .health
        case .gifts: self = .gifts
        case .other: self = .other
        }
    }
}
