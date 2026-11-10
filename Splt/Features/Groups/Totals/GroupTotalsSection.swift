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
            ForEach(model.totals) { totals in
                Section {
                    hero(totals)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if totals.byPerson.contains(where: { $0.paid.minorUnits > 0 }) {
                    Section {
                        let colors = OrbitColors(members: members)
                        RaisedRows {
                            SpendingBarChart(
                                bars: totals.byPerson.filter { $0.paid.minorUnits > 0 }.map {
                                    SpendingBar(label: $0.name, money: $0.paid, color: colors.color(for: $0.personID))
                                }
                            )
                        }
                    } header: {
                        SectionHeader("Paid by person")
                            .padding(.horizontal, Depth.pageMargin + 4)
                    }
                    .raisedSection()
                }
                if totals.byCategory.contains(where: { $0.amount.minorUnits > 0 }) {
                    Section {
                        RaisedRows {
                            SpendingBarChart(
                                bars: totals.byCategory.filter { $0.amount.minorUnits > 0 }
                                    .map { SpendingBar(label: $0.category.title, money: $0.amount, color: nil) }
                            )
                        }
                    } header: {
                        SectionHeader("By category")
                            .padding(.horizontal, Depth.pageMargin + 4)
                    }
                    .raisedSection()
                }
            }
            if model.recapStats != nil {
                Section {
                    Button(action: onRecap) {
                        HStack {
                            Text("Watch the Recap")
                                .foregroundStyle(Ink.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Ink.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .raisedRow()
                }
                .raisedSection()
            }
        }
    }

    private func hero(_ totals: GroupTotals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total spent")
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
            HeroAmount(totals.total, showsSign: false)
                .accessibilityLabel(MoneyFormatting.magnitudeString(totals.total, locale: locale))
            Text("^[\(totals.expenseCount) expense](inflect: true) in \(totals.currencyCode)")
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
            if let summary, totals.currencyCode == model.primaryTotals?.currencyCode {
                Text(summary)
                    .font(.body)
                    .padding(.top, 10)
                    .foregroundStyle(Ink.text)
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
                .cornerRadius(2)
                .foregroundStyle(bar.color ?? Ink.text)
                .annotation(position: .top, alignment: .leading, spacing: 4) {
                    Text(bar.label)
                        .font(.subheadline)
                        .foregroundStyle(Ink.text)
                }
                .annotation(position: .trailing, alignment: .center, spacing: 8) {
                    Text(MoneyFormatting.string(bar.money))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Ink.secondary)
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
