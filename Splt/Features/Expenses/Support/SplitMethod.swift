import SpltCore

/// The ways to divide an expense, in the one order every picker lists them.
enum SplitMethod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case equal
    case percentage
    case shares
    case exact
    case adjustment
    case itemized

    var id: String { rawValue }

    init(_ definition: SplitDefinition) {
        switch definition {
        case .equal: self = .equal
        case .exact: self = .exact
        case .percentages: self = .percentage
        case .shares: self = .shares
        case .adjustments: self = .adjustment
        case .itemized: self = .itemized
        }
    }

    var title: String {
        switch self {
        case .equal: String(localized: "Equally")
        case .exact: String(localized: "Exact amounts")
        case .percentage: String(localized: "Percentages")
        case .shares: String(localized: "Shares")
        case .adjustment: String(localized: "Adjustments")
        case .itemized: String(localized: "By item")
        }
    }

    /// A word short enough for a segmented control.
    var shortTitle: String {
        switch self {
        case .equal: String(localized: "Equal")
        case .exact: String(localized: "Exact")
        case .percentage: String(localized: "%")
        case .shares: String(localized: "Shares")
        case .adjustment: String(localized: "Adjust")
        case .itemized: String(localized: "Items")
        }
    }

    /// What VoiceOver says for `shortTitle`, since a bare "%" is not a word.
    var spokenShortTitle: String {
        self == .percentage ? String(localized: "Percent") : shortTitle
    }

    var symbolName: String {
        switch self {
        case .equal: "equal"
        case .exact: "number"
        case .percentage: "percent"
        case .shares: "chart.pie"
        case .adjustment: "plusminus"
        case .itemized: "list.bullet.rectangle"
        }
    }

    var explanation: String {
        switch self {
        case .equal: String(localized: "Everyone selected pays the same.")
        case .exact: String(localized: "Enter what each person owes. The amounts must add up to the total.")
        case .percentage: String(localized: "Enter each person's percentage. They must add up to 100.")
        case .shares: String(localized: "Each person pays in proportion to their shares, for example 2 shares for a couple and 1 for a single person.")
        case .adjustment: String(localized: "Split equally after adding or taking off an amount for some people.")
        case .itemized: String(localized: "Assign each item to the people who shared it. Tax, tip and discounts are spread in proportion.")
        }
    }
}
