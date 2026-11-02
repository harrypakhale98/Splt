import SwiftUI

/// A short summary of a trip's spending.
struct TripRecapSection: View {
    let recap: TripRecap

    var body: some View {
        Section {
            LabeledContent("Total Spent") {
                MoneyLabel(money: recap.total)
                    .font(.body.weight(.semibold))
            }
            LabeledContent("Per Day") {
                MoneyLabel(money: recap.averagePerDay)
            }
            if let top = recap.topCategory {
                LabeledContent("Biggest Category") {
                    HStack(spacing: 6) {
                        Image(systemName: top.category.symbolName)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(top.category.title)
                    }
                }
            }
            if let title = recap.biggestExpenseTitle, let amount = recap.biggestExpense {
                LabeledContent("Biggest Expense") {
                    VStack(alignment: .trailing) {
                        Text(title)
                        MoneyLabel(money: amount)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Label("Trip Recap", systemImage: "sparkles")
        } footer: {
            Text("^[\(recap.expenseCount) expense](inflect: true) over ^[\(recap.dayCount) day](inflect: true)")
        }
    }
}
