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
                    Label(top.category.title, systemImage: top.category.symbolName)
                }
            }
            if let title = recap.biggestExpenseTitle, let amount = recap.biggestExpense {
                LabeledContent(title) {
                    MoneyLabel(money: amount)
                }
            }
        } header: {
            Label("Trip Recap", systemImage: "sparkles")
        } footer: {
            Text("^[\(recap.expenseCount) expense](inflect: true) over ^[\(recap.dayCount) day](inflect: true)")
        }
    }
}
