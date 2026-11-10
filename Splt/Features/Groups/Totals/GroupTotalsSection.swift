import Accessibility
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
                GroupPaperNote("Totals appear once the group has expenses.")
            }
        } else {
            let members = model.group?.memberIDs ?? []
            // the group's own currency leads, then the one used most; amounts in different
            // currencies are never compared
            let all = GroupTotals.ordered(model.totals, lead: model.primaryTotals?.currencyCode)
            let isMixed = all.count > 1
            if let primary = model.primaryTotals {
                Section {
                    hero(primary, others: all.filter { $0.id != primary.id })
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(all) { totals in
                let people = totals.personRows
                if !people.isEmpty {
                    Section {
                        let _ = PersonColorRevision.shared.value
                        let colors = OrbitColors(members: members)
                        RaisedRows {
                            SpendingBarChart(
                                title: isMixed
                                    ? String(localized: "Paid by person in \(totals.currencyCode)")
                                    : String(localized: "Paid by person"),
                                rows: people,
                                color: { row in row.personID.map { colors.color(for: $0) } }
                            )
                        }
                    } header: {
                        Group {
                            if isMixed { SectionHeader("Paid by person in \(totals.currencyCode)") } else { SectionHeader("Paid by person") }
                        }
                        .padding(.horizontal, Depth.pageMargin + 4)
                    }
                    .raisedSection()
                }
                let categories = totals.categoryRows
                if !categories.isEmpty {
                    Section {
                        RaisedRows {
                            SpendingBarChart(
                                title: isMixed
                                    ? String(localized: "By category in \(totals.currencyCode)")
                                    : String(localized: "By category"),
                                rows: categories,
                                // only the largest category speaks; the rest stay grey, as in the recap
                                color: { row in row.id == categories.first?.id ? Ink.text : Ink.tertiary }
                            )
                        }
                    } header: {
                        Group {
                            if isMixed { SectionHeader("By category in \(totals.currencyCode)") } else { SectionHeader("By category") }
                        }
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

    /// The one big figure for the main currency, with any other currency as a quiet line under it.
    private func hero(_ totals: GroupTotals, others: [GroupTotals]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total spent")
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
            // refunds can outweigh spending, and then the total keeps its minus sign
            HeroAmount(totals.total, showsSign: totals.total.minorUnits < 0)
                .accessibilityLabel(signed(totals.total))
            Text("^[\(totals.expenseCount) expense](inflect: true) in \(totals.currencyCode)")
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
            ForEach(others) { other in
                HStack(spacing: 6) {
                    Text(signed(other.total))
                        .font(Typeface.figure)
                    Text("^[\(other.expenseCount) expense](inflect: true) in \(other.currencyCode)")
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                }
            }
            if let summary {
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

    private func signed(_ money: Money) -> String {
        MoneyFormatting.string(money, locale: locale, showsSign: money.minorUnits < 0)
    }
}

/// Horizontal bars for one currency, largest first, with refunds running left from a zero line so the
/// bars are to scale and add up to the total. The name and amount sit above each bar, and the
/// amount drops to its own line at accessibility sizes so it never runs off the card.
private struct SpendingBarChart: View {
    let title: String
    let rows: [SpendingRow]
    /// A person's color, or nil to use ink.
    let color: (SpendingRow) -> Color?

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let scale = SpendingScale(values: rows.map(\.money.minorUnits))
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    caption(for: row)
                    SpendingBarTrack(scale: scale, value: row.money.minorUnits, color: color(row) ?? Ink.text)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(SpendingRow.spokenSummary(rows, locale: locale))
        .accessibilityChartDescriptor(SpendingChartDescriptor(title: title, rows: rows, locale: locale))
    }

    @ViewBuilder
    private func caption(for row: SpendingRow) -> some View {
        let name = Text(row.label)
            .font(.subheadline)
            .foregroundStyle(Ink.text)
        let amount = Text(row.amountText(locale: locale))
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(Ink.secondary)
            .lineLimit(1)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                name
                amount.minimumScaleFactor(0.5)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                name
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                amount
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            }
        }
    }
}

/// One bar, placed on the chart's shared scale. A hairline marks zero when any bar is a refund.
private struct SpendingBarTrack: View {
    let scale: SpendingScale
    let value: Int64
    let color: Color

    var body: some View {
        let bar = scale.bar(for: value)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                if scale.hasNegatives {
                    Rectangle()
                        .fill(Ink.hairline)
                        .frame(width: 1)
                        .offset(x: width * scale.zero - 0.5)
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(width * bar.length, 2))
                    .offset(x: width * bar.start)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// The chart as data for Audio Graphs.
private struct SpendingChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let rows: [SpendingRow]
    let locale: Locale

    func makeChartDescriptor() -> AXChartDescriptor {
        let code = rows.first?.money.currencyCode ?? "USD"
        let locale = self.locale
        let names = SpendingRow.distinctLabels(rows)
        let values = rows.map { NSDecimalNumber(decimal: $0.money.decimalValue).doubleValue }
        let low = min(0, values.min() ?? 0)
        let high = max(0, values.max() ?? 0)
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Name"), categoryOrder: names)
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Amount"), range: low...max(high, low + 1), gridlinePositions: []
        ) { value in
            value.formatted(.currency(code: code).locale(locale))
        }
        let series = AXDataSeriesDescriptor(
            name: title, isContinuous: false,
            dataPoints: zip(names, values).map { AXDataPoint(x: $0, y: $1, additionalValues: [], label: nil) }
        )
        return AXChartDescriptor(
            title: title, summary: SpendingRow.spokenSummary(rows, locale: locale),
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}
