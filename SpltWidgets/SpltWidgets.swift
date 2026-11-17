import AppIntents
import SwiftUI
import WidgetKit

@main
struct SpltWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        ToSplitWidget()
        AddExpenseControl()
        SplitLastPaymentControl()
    }
}

// MARK: Controls
// Each one only opens the app, so none shows anything about your payments or balances.

struct AddExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SpltWidgetKind.addExpenseControl) {
            ControlWidgetButton(action: OpenAddExpenseIntent()) {
                Label("Add Expense", systemImage: "plus")
            }
        }
        .displayName("Add Expense")
        .description("Opens a new expense in the group you used last.")
    }
}

struct SplitLastPaymentControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SpltWidgetKind.splitLastPaymentControl) {
            ControlWidgetButton(action: SplitLastPaymentIntent()) {
                // To Split's mark: this is the To Split control too, opening the list when nothing waits
                Label("Split Last Payment", systemImage: ToSplitWidget.symbol)
            }
        }
        .displayName("Split Last Payment")
        .description("Opens your last payment waiting in To Split, ready to split, or To Split when none is waiting.")
    }
}
