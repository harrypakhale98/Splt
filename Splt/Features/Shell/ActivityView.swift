import SwiftUI

struct ActivityView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.activityPath) {
            EmptyStateView(
                title: "No Activity Yet",
                systemImage: "list.bullet.rectangle",
                description: "Expenses and payments from your groups will show up here.",
                actionTitle: "Add Expense",
                action: { router.present(.addExpense) }
            )
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Expense", systemImage: "plus") {
                        router.present(.addExpense)
                    }
                }
            }
            .routeDestinations()
        }
    }
}

#Preview {
    ActivityView()
        .environment(Router())
}
