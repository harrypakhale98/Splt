import SpltCore
import SwiftUI

struct ExpenseHeaderSection: View {
    let model: ExpenseDetailModel
    let expense: Expense

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    CategoryBadge(category: expense.category)
                    VStack(alignment: .leading) {
                        Text(expense.title).font(.title2.weight(.semibold))
                        Text(expense.category.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                MoneyLabel(money: expense.total)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(expense.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .foregroundStyle(.secondary)
                if let group = model.group {
                    Label(group.name, systemImage: group.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if expense.isRefund {
                    Label("Refund", systemImage: "arrow.uturn.backward.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct PaidBySection: View {
    let model: ExpenseDetailModel
    @Environment(\.locale) private var locale

    var body: some View {
        Section("Paid By") {
            ForEach(model.payerLines, id: \.person.id) { line in
                HStack {
                    AvatarView(name: line.person.name, size: 32)
                    Text(line.name)
                    Spacer(minLength: 8)
                    MoneyLabel(money: line.amount)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    String(localized: "\(line.name) paid \(MoneyFormatting.magnitudeString(line.amount, locale: locale))")
                )
            }
        }
    }
}
