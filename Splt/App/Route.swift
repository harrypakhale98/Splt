import Foundation

/// Screens that can be pushed onto a tab's navigation stack.
/// A new case needs a matching branch in `RouteDestinationView`.
enum Route: Hashable, Sendable {
    case group(UUID)
    case friend(UUID)
    /// An expense, by its id.
    case expense(UUID)
    /// The recurring expenses of a group, by group id.
    case recurringExpenses(UUID)
    /// Your share of everything, from the top of Activity.
    case spending
}

/// Full screen flows presented as sheets over the tab bar.
enum AppSheet: String, Identifiable, Hashable, Sendable {
    case addExpense
    case newGroup
    case newFriend
    case account

    var id: String { rawValue }
}
