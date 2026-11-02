import SpltCore
import SwiftUI

extension View {
    /// Registers every pushable `Route` on a navigation stack.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteDestinationView(route: route)
                .modifier(ZoomDestination(route: route))
        }
    }
}

struct RouteDestinationView: View {
    let route: Route

    var body: some View {
        switch route {
        case .group(let id):
            GroupDetailView(groupID: GroupID(rawValue: id))
        case .friend(let id):
            FriendDetailView(friendID: PersonID(rawValue: id))
        case .settings:
            SettingsView()
        case .expense(let id):
            ExpenseDetailView(expenseID: ExpenseID(rawValue: id))
        case .recurringExpenses(let id):
            RecurringExpensesView(groupID: GroupID(rawValue: id))
        case .groupSettings(let id):
            GroupSettingsView(groupID: GroupID(rawValue: id), isPushed: true)
        }
    }
}

#Preview("Group") {
    NavigationStack { RouteDestinationView(route: .group(UUID())) }
}

#Preview("Friend") {
    NavigationStack { RouteDestinationView(route: .friend(UUID())) }
}
