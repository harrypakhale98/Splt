import SwiftUI

/// A short summary of a trip's spending.
struct TripRecapSection: View {
    let recap: TripRecap
    let onRecap: () -> Void

    var body: some View {
        Section {
            LabeledContent("Total Spent") {
                MoneyLabel(money: recap.total)
                    .font(.body.weight(.semibold))
            }
            LabeledContent("Per Day") {
                MoneyLabel(money: recap.averagePerDay)
            }
            Button(action: onRecap) {
                Label("Watch the Recap", systemImage: "sparkles.rectangle.stack")
            }
        } header: {
            Label("Trip Recap", systemImage: "sparkles")
        } footer: {
            Text("^[\(recap.expenseCount) expense](inflect: true) over ^[\(recap.dayCount) day](inflect: true)")
        }
    }
}
