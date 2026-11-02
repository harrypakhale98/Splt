import SpltCore
import SwiftUI

struct ExpenseHeaderSection: View {
    let model: ExpenseDetailModel
    let expense: Expense
    @ScaledMetric(relativeTo: .title2) private var badge: CGFloat = 56

    var body: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: expense.category.symbolName)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(width: badge, height: badge)
                    .background(.tint.opacity(0.15), in: .circle)
                    .accessibilityHidden(true)
                Text(expense.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                HeroAmount(expense.total, showsSign: false)
                Text(expense.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .font(.subheadline)
                    .foregroundStyle(.legible)
                if !model.payerLines.isEmpty {
                    HStack(spacing: 8) {
                        if model.payerLines.count == 1, let only = model.payerLines.first {
                            AvatarView(person: only.person, members: model.memberIDs, size: 28)
                        } else {
                            AvatarStack(model.payerLines.map(\.person), members: model.memberIDs, size: 28)
                        }
                        Text(payerText).font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 4)
                }
                HStack(spacing: 12) {
                    if let group = model.group {
                        Label(group.name, systemImage: group.symbol)
                    }
                    if expense.isRefund {
                        Label("Refund", systemImage: "arrow.uturn.backward.circle")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.legible)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var payerText: String {
        ExpenseSummary.payerText(
            Dictionary(uniqueKeysWithValues: model.payerLines.map { ($0.person.id, $0.amount) }),
            currentPerson: model.me?.id, names: model.people.mapValues(\.name)
        )
    }
}

struct PaidBySection: View {
    let model: ExpenseDetailModel
    @Environment(\.locale) private var locale

    var body: some View {
        Section(header: Text("Paid By").foregroundStyle(.legible)) {
            ForEach(model.payerLines, id: \.person.id) { line in
                HStack {
                    AvatarView(person: line.person, members: model.memberIDs, size: 32)
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
