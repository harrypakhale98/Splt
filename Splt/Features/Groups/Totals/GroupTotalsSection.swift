import Charts
import SpltCore
import SwiftUI

/// Spending by person and by category: a big total, a sentence from the on-device model when it is
/// available, and bars in each person's color.
struct GroupTotalsSection: View {
    let model: GroupDetailViewModel
    /// A sentence about the spending, when the summarizer had something to say.
    let summary: String?
    var onRecap: () -> Void = {}

    @Environment(\.locale) private var locale

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
            let members = model.group?.memberIDs ?? []
            if let group = model.group, let stats = model.recapStats {
                RecapEntryCard(group: group, stats: stats, members: model.members, onOpen: onRecap)
            }
            ForEach(model.totals) { totals in
                Section {
                    hero(totals)
                }

                if totals.byPerson.contains(where: { $0.paid.minorUnits > 0 }) {
                    Section("Paid by Person") {
                        let colors = OrbitColors(members: members)
                        SpendingBarChart(
                            bars: totals.byPerson.filter { $0.paid.minorUnits > 0 }.map {
                                SpendingBar(label: $0.name, money: $0.paid, color: colors.color(for: $0.personID))
                            }
                        )
                    }
                }
                if totals.byCategory.contains(where: { $0.amount.minorUnits > 0 }) {
                    Section("By Category") {
                        SpendingBarChart(
                            bars: totals.byCategory.filter { $0.amount.minorUnits > 0 }
                                .map { SpendingBar(label: $0.category.title, money: $0.amount, color: nil) }
                        )
                    }
                }
            }
        }
    }

    private func hero(_ totals: GroupTotals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total Spent")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HeroAmount(totals.total, showsSign: false)
                .accessibilityLabel(MoneyFormatting.magnitudeString(totals.total, locale: locale))
            Text("^[\(totals.expenseCount) expense](inflect: true) in \(totals.currencyCode)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let summary, totals.currencyCode == model.primaryTotals?.currencyCode {
                Label(summary, systemImage: "sparkles")
                    .font(.body)
                    .fontDesign(.serif)
                    .padding(.top, 10)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SpendingBar: Identifiable, Equatable {
    var label: String
    var money: Money
    /// A person's color, or nil to use the accent.
    var color: Color?

    var id: String { label }

    /// Chart axes need a floating point value. This is for drawing only; stored amounts stay in minor units.
    var chartValue: Double {
        NSDecimalNumber(decimal: money.decimalValue).doubleValue
    }
}

private struct SpendingBarChart: View {
    let bars: [SpendingBar]

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 58

    var body: some View {
        let largest = bars.map(\.chartValue).max() ?? 1
        Chart(bars) { bar in
            BarMark(x: .value("Amount", bar.chartValue), y: .value("Name", bar.label), height: .fixed(14))
                .cornerRadius(7)
                .foregroundStyle(bar.color ?? Color.accentColor)
                .annotation(position: .top, alignment: .leading, spacing: 4) {
                    Text(bar.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .annotation(position: .trailing, alignment: .center, spacing: 8) {
                    Text(MoneyFormatting.string(bar.money))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(bar.label)
                .accessibilityValue(MoneyFormatting.magnitudeString(bar.money))
        }
        .chartXScale(domain: 0...(largest * 1.45))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: max(CGFloat(bars.count) * rowHeight, rowHeight * 1.5))
        .padding(.vertical, 4)
    }
}
