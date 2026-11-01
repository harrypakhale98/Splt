import SpltCore
import SwiftUI

/// The recurring expenses of one group. Pushed with `Route.recurringExpenses`.
struct RecurringExpensesView: View {
    let groupID: GroupID

    var body: some View {
        EmptyStateView(
            title: "No Recurring Expenses",
            systemImage: "arrow.triangle.2.circlepath",
            description: "Expenses that repeat show up here."
        )
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
    }
}
