import SpltCore
import SwiftUI

/// Everything about one expense. Pushed with `Route.expense`.
struct ExpenseDetailView: View {
    let expenseID: ExpenseID

    @Environment(\.dataServices) private var services

    var body: some View {
        Group {
            if let expense = services.flatMap({ try? $0.expenses.expense(id: expenseID) }) {
                List {
                    Section {
                        LabeledContent("Amount") { MoneyLabel(money: expense.total) }
                        LabeledContent("Date") { Text(expense.date, format: .dateTime.day().month().year()) }
                        LabeledContent("Category") { Label(expense.category.title, systemImage: expense.category.symbolName) }
                    }
                }
                .navigationTitle(expense.title)
            } else {
                EmptyStateView(
                    title: "Expense Not Found",
                    systemImage: "questionmark.circle",
                    description: "This expense may have been removed."
                )
                .navigationTitle("Expense")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
