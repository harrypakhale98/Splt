import SpltCore
import SwiftUI

/// What a group expense row says, worked out in plain code so it can be tested.
struct ExpenseRowSummary: Equatable {
    var payerText: String
    /// The people who paid, for the colored markers.
    var payers: [PersonID]
    /// What you paid minus what you owe. Nil when you are not part of the expense.
    var yourNet: Money?

    init(expense: Expense, currentPerson: PersonID?, names: [PersonID: String]) {
        payerText = ExpenseSummary.payerText(expense.payers, currentPerson: currentPerson, names: names)
        payers = expense.payers.keys.sorted()
        yourNet = nil
        guard let currentPerson, expense.participants.contains(currentPerson),
              let nets = try? expense.netBalances() else { return }
        yourNet = nets[currentPerson] ?? .zero(currencyCode: expense.total.currencyCode)
    }

    var caption: String? {
        guard let yourNet else { return nil }
        if yourNet.minorUnits > 0 { return String(localized: "you lent") }
        if yourNet.minorUnits < 0 { return String(localized: "you owe") }
        return String(localized: "even")
    }

    /// The short line under the total: "you owe $12.00", "you lent $20.00" or "even".
    func detail(locale: Locale) -> String? {
        guard let yourNet, let caption else { return nil }
        if yourNet.isZero { return caption }
        return "\(caption) \(MoneyFormatting.magnitudeString(yourNet, locale: locale))"
    }
}

/// One expense in a group: a quiet category glyph, who paid with their color, and what it means for you.
struct GroupExpenseRow: View {
    let expense: Expense
    let currentPerson: PersonID?
    let people: [Person]
    let members: [PersonID]

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        let summary = ExpenseRowSummary(
            expense: expense, currentPerson: currentPerson,
            names: Dictionary(people.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        )
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Image(systemName: expense.category.symbolName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .layoutPriority(1)
                HStack(spacing: 6) {
                    payerMarkers(summary.payers)
                    Text(summary.payerText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            trailing(summary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(summary))
    }

    private func trailing(_ summary: ExpenseRowSummary) -> some View {
        Group {
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                MoneyLabel(money: expense.total)
                    .font(.body.weight(.semibold))
                if let net = summary.yourNet, let detail = summary.detail(locale: locale) {
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(net.minorUnits > 0 ? Color.green : (net.minorUnits < 0 ? Color.red : Color.secondary))
                } else {
                    Text("Not involved")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
    }

    private func payerMarkers(_ ids: [PersonID]) -> some View {
        HStack(spacing: -3) {
            ForEach(ids.prefix(3), id: \.self) { id in
                Circle()
                    .fill(PersonPalette.color(for: id, in: members))
                    .frame(width: 10, height: 10)
                    .overlay { Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5) }
            }
        }
        .accessibilityHidden(true)
    }

    private func accessibilityText(_ summary: ExpenseRowSummary) -> String {
        let total = MoneyFormatting.magnitudeString(expense.total, locale: locale)
        var parts = [expense.title, "\(summary.payerText) \(total)"]
        if let detail = summary.detail(locale: locale) {
            parts.append(detail)
        } else {
            parts.append(String(localized: "You are not involved"))
        }
        parts.append(expense.date.formatted(date: .long, time: .omitted))
        return parts.joined(separator: ". ")
    }
}
