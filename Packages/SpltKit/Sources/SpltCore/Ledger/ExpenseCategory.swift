/// A coarse category for an expense. Unknown values from newer app versions decode as `.other`.
public enum ExpenseCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case general
    case groceries
    case dining
    case drinks
    case transport
    case fuel
    case travel
    case lodging
    case entertainment
    case utilities
    case rent
    case home
    case shopping
    case health
    case gifts
    case education
    case subscriptions
    case pets
    case other

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseCategory(rawValue: raw) ?? .other
    }
}
