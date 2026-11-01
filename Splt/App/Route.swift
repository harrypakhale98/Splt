import Foundation

/// Screens that can be pushed onto a tab's navigation stack.
/// Later features add cases here and a matching branch in `RouteDestinationView`.
enum Route: Hashable, Sendable {
    case group(UUID)
    case friend(UUID)
    case settings
    /// An expense, by its id.
    case expense(UUID)
    /// The recurring expenses of a group, by group id.
    case recurringExpenses(UUID)
}

/// Full screen flows presented as sheets over the tab bar.
enum AppSheet: String, Identifiable, Hashable, Sendable {
    case addExpense
    case newGroup
    case newFriend

    var id: String { rawValue }
}
