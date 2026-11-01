import SpltCore
import SwiftUI

/// Adds or edits an expense. Present it in a sheet; it brings its own navigation stack.
struct ExpenseFormView: View {
    let mode: ExpenseFormMode

    @Environment(\.dataServices) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.largeTitle.monospacedDigit())
                TextField("What was it for?", text: $title)
            }
            .navigationTitle(isEditing ? "Edit Expense" : "New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !amountText.isEmpty
    }

    private func save() {
        guard let services, case .add(let groupID, _) = mode,
              let group = try? services.groups.group(id: groupID),
              let me = try? services.people.me(),
              let total = try? Money(parsing: amountText, currencyCode: group.currencyCode) else { return }
        let expense = Expense(
            groupID: groupID, title: title, total: total, date: Date(),
            paidBy: me.id, split: .equal(participants: Set(group.memberIDs))
        )
        if (try? services.expenses.add(expense)) != nil {
            dismiss()
        }
    }
}
