import SpltCore
import SwiftUI

/// One expense in a list: category symbol, title, who paid, the current person's share and the date.
struct ExpenseRowView: View {
    let expense: Expense
    let currentPerson: PersonID?
    /// Names for the payers. Anyone missing is looked up from the app's data.
    var people: [Person]

    @Environment(\.dataServices) private var services
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var fetched: [PersonID: Person] = [:]

    init(expense: Expense, currentPerson: PersonID?, people: [Person] = []) {
        self.expense = expense
        self.currentPerson = currentPerson
        self.people = people
    }

    init(expense: Expense, currentPerson: Person, people: [Person] = []) {
        self.init(expense: expense, currentPerson: currentPerson.id, people: people + [currentPerson])
    }

    init(row: ExpenseRow, currentPerson: PersonID?) {
        self.init(expense: row.expense, currentPerson: currentPerson, people: row.payers)
    }

    private var summary: ExpenseSummary {
        var names = Dictionary(fetched.map { ($0.key, $0.value.name) }, uniquingKeysWith: { first, _ in first })
        for person in people { names[person.id] = person.name }
        return ExpenseSummary(expense: expense, currentPerson: currentPerson, names: names)
    }

    private var unresolvedPayers: [PersonID] {
        let known = Set(people.map(\.id)).union(fetched.keys)
        return expense.payers.keys.filter { !known.contains($0) && $0 != currentPerson }.sorted()
    }

    var body: some View {
        let summary = summary
        HStack(spacing: 12) {
            CategoryBadge(category: expense.category)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    details(summary)
                    shareText(summary)
                }
            } else {
                details(summary)
                Spacer(minLength: 8)
                shareText(summary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .strikethrough(expense.isDeleted)
        .opacity(expense.isDeleted ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(summary))
        .task(id: unresolvedPayers) { await resolvePayers() }
    }

    private func details(_ summary: ExpenseSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(expense.title)
                .font(.headline)
            Text("\(summary.paidBy) \(MoneyFormatting.magnitudeString(expense.total, locale: locale))")
                .font(.subheadline)
                .foregroundStyle(.legible)
            Text(expense.date, format: .dateTime.day().month(.abbreviated).year())
                .font(.caption)
                .foregroundStyle(.legible)
        }
    }

    @ViewBuilder
    private func shareText(_ summary: ExpenseSummary) -> some View {
        if expense.isDeleted {
            Text("Deleted")
                .font(.subheadline)
                .foregroundStyle(.legible)
        } else if let share = summary.myShare {
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                MoneyLabel(money: share)
                    .font(.body.weight(.semibold))
                Text("Your share")
                    .font(.caption)
                    .foregroundStyle(.legible)
            }
        } else {
            Text("Not involved")
                .font(.subheadline)
                .foregroundStyle(.legible)
        }
    }

    private func accessibilityText(_ summary: ExpenseSummary) -> String {
        let total = MoneyFormatting.magnitudeString(expense.total, locale: locale)
        let date = expense.date.formatted(date: .long, time: .omitted)
        var parts = [expense.title, "\(summary.paidBy) \(total)"]
        if expense.isDeleted {
            parts.append(String(localized: "Deleted"))
        } else if let share = summary.myShare {
            let amount = MoneyFormatting.magnitudeString(share, locale: locale)
            parts.append(String(localized: "Your share \(amount)"))
        } else {
            parts.append(String(localized: "You are not involved"))
        }
        parts.append(date)
        return parts.joined(separator: ". ")
    }

    private func resolvePayers() async {
        guard let services, !unresolvedPayers.isEmpty else { return }
        let found = (try? services.people.people(ids: unresolvedPayers)) ?? []
        for person in found { fetched[person.id] = person }
    }
}

/// A category symbol on a tinted rounded square.
struct CategoryBadge: View {
    let category: ExpenseCategory
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 40

    private var side: CGFloat { min(scaledSide, 60) }

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: side * 0.45, weight: .medium))
            .foregroundStyle(.tint)
            .frame(width: side, height: side)
            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: side * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Rows") {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.name == "Lisbon Trip" }) ?? nil
    let me = try? services.people.me()
    let expenses = trip.flatMap { try? services.expenses.expenses(in: $0.id, includeDeleted: true) } ?? []
    NavigationStack {
        List(expenses) { expense in
            ExpenseRowView(expense: expense, currentPerson: me?.id)
        }
        .navigationTitle("Lisbon Trip")
    }
    .environment(\.dataServices, services)
}

#Preview("Large text") {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.name == "Lisbon Trip" }) ?? nil
    let me = try? services.people.me()
    let expenses = trip.flatMap { try? services.expenses.expenses(in: $0.id) } ?? []
    NavigationStack {
        List(expenses.prefix(3)) { expense in
            ExpenseRowView(expense: expense, currentPerson: me?.id)
        }
    }
    .environment(\.dataServices, services)
    .dynamicTypeSize(.accessibility3)
}
#endif
