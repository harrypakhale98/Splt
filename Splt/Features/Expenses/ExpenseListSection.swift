import SpltCore
import SwiftUI

/// Rows for a list of expenses, each pushing the expense detail. Put it inside a `List`.
struct ExpenseListSection<Header: View>: View {
    let rows: [ExpenseRow]
    let currentPerson: PersonID?
    @ViewBuilder var header: () -> Header

    var body: some View {
        Section {
            ForEach(rows) { row in
                NavigationLink(value: Route.expense(row.expense.id.rawValue)) {
                    ExpenseRowView(row: row, currentPerson: currentPerson)
                }
            }
        } header: {
            header()
        }
    }
}

extension ExpenseListSection where Header == EmptyView {
    init(rows: [ExpenseRow], currentPerson: PersonID?) {
        self.init(rows: rows, currentPerson: currentPerson) { EmptyView() }
    }
}
