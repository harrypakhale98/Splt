import SpltCore
import SwiftUI

struct ExpenseHeaderSection: View {
    let model: ExpenseDetailModel
    let expense: Expense

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Text(expense.title)
                    .font(Typeface.heading)
                    .multilineTextAlignment(.center)
                HeroAmount(expense.total, showsSign: false)
                Text(quietLine)
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
                ShareStrip(
                    colors: model.shareLines.map { PersonPalette.color(for: $0.person.id) },
                    weights: model.shareLines.map { Double(max($0.share.minorUnits, 0)) }
                )
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var quietLine: String {
        var parts = [payerText, expense.date.formatted(.dateTime.day().month(.abbreviated).year())]
        if expense.isRefund { parts.append(String(localized: "Refund")) }
        return parts.joined(separator: " \u{00B7} ")
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
        if model.payerLines.count > 1 {
            Section {
                RaisedRows {
                    ForEach(model.payerLines, id: \.person.id) { line in
                        HStack {
                            AvatarView(person: line.person, members: model.memberIDs, size: 28)
                            Text(line.name)
                            Spacer(minLength: 8)
                            MoneyLabel(money: line.amount).font(Typeface.figure)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            String(localized: "\(line.name) paid \(MoneyFormatting.magnitudeString(line.amount, locale: locale))")
                        )
                    }
                }
            } header: {
                SectionHeader("Paid by")
            }
        }
    }
}
