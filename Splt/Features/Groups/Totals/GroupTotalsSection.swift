import Charts
import SpltCore
import SwiftUI

/// Spending by person and by category, with a sentence from the on-device model when it is available.
struct GroupTotalsSection: View {
    let model: GroupDetailViewModel
    /// A sentence about the spending, when the summarizer had something to say.
    let summary: String?

    var body: some View {
        if model.totals.isEmpty {
            Section {
                EmptyStateView(
                    title: "No Totals Yet",
                    systemImage: "chart.bar",
                    description: "Totals appear once the group has expenses."
                )
                .listRowBackground(Color.clear)
            }
        } else {
            if let summary {
                Section {
                    Label(summary, systemImage: "sparkles")
                }
            }
            ForEach(model.totals) { totals in
                Section {
                    LabeledContent("Total Spent") {
                        MoneyLabel(money: totals.total)
                            .font(.body.weight(.semibold))
                    }
                    LabeledContent("Expenses") {
                        Text(totals.expenseCount, format: .number)
                            .monospacedDigit()
                    }
                } header: {
                    Text(totals.currencyCode)
                }

                if totals.byPerson.contains(where: { $0.paid.minorUnits > 0 }) {
                    Section("Paid by Person") {
                        SpendingBarChart(
                            bars: totals.byPerson.filter { $0.paid.minorUnits > 0 }
                                .map { SpendingBar(label: $0.name, money: $0.paid) }
                        )
                    }
                }
                if totals.byCategory.contains(where: { $0.amount.minorUnits > 0 }) {
                    Section("By Category") {
                        SpendingBarChart(
                            bars: totals.byCategory.filter { $0.amount.minorUnits > 0 }
                                .map { SpendingBar(label: $0.category.title, money: $0.amount) }
                        )
                    }
                }
            }
        }
    }
}

struct SpendingBar: Identifiable, Equatable {
    var label: String
    var money: Money

    var id: String { label }

    /// Chart axes need a floating point value. This is for drawing only; stored amounts stay in minor units.
    var chartValue: Double {
        NSDecimalNumber(decimal: money.decimalValue).doubleValue
    }
}

private struct SpendingBarChart: View {
    let bars: [SpendingBar]

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 36

    var body: some View {
        let largest = bars.map(\.chartValue).max() ?? 1
        Chart(bars) { bar in
            BarMark(x: .value("Amount", bar.chartValue), y: .value("Name", bar.label))
                .foregroundStyle(.tint)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(MoneyFormatting.string(bar.money))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(bar.label)
                .accessibilityValue(MoneyFormatting.magnitudeString(bar.money))
        }
        .chartXScale(domain: 0...(largest * 1.45))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
            }
        }
        .frame(height: max(CGFloat(bars.count) * rowHeight, rowHeight * 1.5))
        .padding(.vertical, 4)
    }
}
