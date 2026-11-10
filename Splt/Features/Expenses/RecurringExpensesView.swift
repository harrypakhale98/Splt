import SpltCore
import SwiftUI

/// The recurring expenses of one group. Pushed with `Route.recurringExpenses`.
struct RecurringExpensesView: View {
    let groupID: GroupID

    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            RecurringExpensesScreen(groupID: groupID, services: services)
        } else {
            EmptyStateView.dataUnavailable
                .navigationTitle("Recurring")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct RecurringExpensesScreen: View {
    @State private var model: RecurringExpensesModel
    @State private var editing: RecurringExpense?
    @State private var adding = false
    @State private var pendingDelete: RecurringExpense?

    init(groupID: GroupID, services: DataServices) {
        _model = State(initialValue: RecurringExpensesModel(groupID: groupID, services: services))
    }

    var body: some View {
        List {
            Section {
                RaisedRows {
                    ForEach(model.templates) { template in
                        Button { editing = template } label: {
                            RecurringRow(model: model, template: template)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = template }
                        }
                        .swipeActions(edge: .leading) {
                            Button(template.isActive ? "Pause" : "Resume", systemImage: template.isActive ? "pause" : "play") {
                                model.setActive(!template.isActive, for: template)
                            }
                            .tint(Ink.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .overlay {
            if model.templates.isEmpty {
                EmptyStateView(
                    title: "No Recurring Expenses",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: "Rent, subscriptions and bills can be added once and repeat on their own.",
                    actionTitle: "Add Recurring Expense",
                    action: { adding = true }
                )
            }
        }
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { adding = true }
            }
        }
        .sheet(item: $editing, onDismiss: model.reload) { template in
            ExpenseFormView(mode: .editRecurring(template))
        }
        .sheet(isPresented: $adding, onDismiss: model.reload) {
            ExpenseFormView(mode: .add(groupID: model.groupID, prefill: ExpenseDraft(repeats: .monthly)))
        }
        .confirmationDialog(
            "Delete this recurring expense?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { model.delete(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Expenses it already made stay in the group.")
        }
        .alert("Couldn't Finish", isPresented: Binding(
            get: { model.actionError != nil }, set: { if !$0 { model.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }
}

private struct RecurringRow: View {
    let model: RecurringExpensesModel
    let template: RecurringExpense
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: template.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title).font(.headline)
                Text(template.rule.frequency.title).font(.footnote).foregroundStyle(Ink.secondary)
                Text(statusText).font(.caption).foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 8)
            MoneyLabel(money: template.total).font(Typeface.figure)
        }
        .opacity(template.isActive ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
        .accessibilityHint("Opens the recurring expense to edit")
    }

    private var statusText: String {
        if !template.isActive { return String(localized: "Paused") }
        guard let next = model.nextDate(for: template) else { return String(localized: "Finished") }
        return String(localized: "Next \(next.formatted(date: .abbreviated, time: .omitted))")
    }

    private var spokenText: String {
        let amount = MoneyFormatting.magnitudeString(template.total, locale: locale)
        return "\(template.title). \(template.rule.frequency.title). \(amount). \(model.payerSummary(for: template)). \(statusText)"
    }
}

#if DEBUG
#Preview("With expenses") {
    let scene = ExpensePreviewSupport.scene()
    let trip = scene.trip
    let rule = RecurrenceRule(frequency: .monthly, startDate: Date())
    let rent = RecurringExpense(
        groupID: trip.flat.id, title: "Rent", total: Money(minorUnits: 120_000, currencyCode: "EUR"), category: .rent,
        payers: [trip.me.id: Money(minorUnits: 120_000, currencyCode: "EUR")],
        split: .equal(participants: [trip.me.id, trip.maya.id]), rule: rule
    )
    let internet = RecurringExpense(
        groupID: trip.flat.id, title: "Internet", total: Money(minorUnits: 3_990, currencyCode: "EUR"), category: .utilities,
        payers: [trip.maya.id: Money(minorUnits: 3_990, currencyCode: "EUR")],
        split: .equal(participants: [trip.me.id, trip.maya.id]), rule: rule, isActive: false
    )
    try? scene.services.recurring.add(rent)
    try? scene.services.recurring.add(internet)
    return NavigationStack { RecurringExpensesView(groupID: trip.flat.id) }
        .environment(\.dataServices, scene.services)
}

#Preview("Empty") {
    let scene = ExpensePreviewSupport.scene()
    NavigationStack { RecurringExpensesView(groupID: scene.trip.flat.id) }
        .environment(\.dataServices, scene.services)
}
#endif
