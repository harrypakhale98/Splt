import AppIntents
import SwiftUI
import WidgetKit

@main
struct SpltWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ToSplitWidget()
        BalanceWidget()
        ToSplitControl()
        AddExpenseControl()
        SplitLastPaymentControl()
        TripLiveActivityWidget()
    }
}

// MARK: Controls
// Each one only opens the app, so none shows anything about your payments or balances.

struct ToSplitControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SpltWidgetKind.inboxControl) {
            ControlWidgetButton(action: OpenInboxIntent()) {
                Label("To Split", systemImage: ToSplitWidget.symbol)
            }
        }
        .displayName("To Split")
        .description("Opens the payments waiting to be split.")
    }
}

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
                Label("Split Last Payment", systemImage: "creditcard")
            }
        }
        .displayName("Split Last Payment")
        .description("Opens the newest payment in To Split, ready to split.")
    }
}
