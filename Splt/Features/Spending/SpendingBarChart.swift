import Accessibility
import SpltCore
import SwiftUI

/// Horizontal bars for one currency, largest first, with refunds running left from a zero line so the
/// bars are to scale and add up to the total. The name and amount sit above each bar, and the
/// amount drops to its own line at accessibility sizes so it never runs off the card.
struct SpendingBarChart: View {
    let title: String
    let rows: [SpendingRow]
    /// A person's color, or nil to use ink.
    let color: (SpendingRow) -> Color?
    /// Opens the expenses behind a bar.
    var onSelect: ((SpendingRow) -> Void)?

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let scale = SpendingScale(values: rows.map(\.money.minorUnits))
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows) { row in
                Button {
                    onSelect?(row)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        caption(for: row)
                        SpendingBarTrack(scale: scale, value: row.money.minorUnits, color: color(row) ?? Ink.text)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SpendingRowButtonStyle())
                .disabled(onSelect == nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SpendingRow.spokenSummary([row], locale: locale))
                .accessibilityHint(onSelect == nil ? "" : String(localized: "Shows these expenses"))
                .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
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
                HStack(spacing: 8) {
                    amount.minimumScaleFactor(0.5)
                    if onSelect != nil { chevron }
                }
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
                if onSelect != nil { chevron }
            }
        }
    }
}

private extension SpendingBarChart {
    /// The same quiet chevron as other rows that open something.
    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Ink.tertiary)
            .accessibilityHidden(true)
    }
}

/// A bar row that dims a little while pressed, like the app's other rows.
private struct SpendingRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .motion(Motion.quick, value: configuration.isPressed)
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
