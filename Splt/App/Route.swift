import Foundation

/// Screens that can be pushed onto a tab's navigation stack.
/// A new case needs a matching branch in `RouteDestinationView`.
enum Route: Hashable, Sendable {
    case group(UUID)
    case friend(UUID)
    case settings
    /// An expense, by its id.
    case expense(UUID)
    /// The recurring expenses of a group, by group id.
    case recurringExpenses(UUID)
    /// The settings of a group, by group id, pushed instead of presented as a sheet.
    case groupSettings(UUID)
}

/// Full screen flows presented as sheets over the tab bar.
enum AppSheet: String, Identifiable, Hashable, Sendable {
    case addExpense
    case newGroup
    case newFriend
    case account

    var id: String { rawValue }
}
