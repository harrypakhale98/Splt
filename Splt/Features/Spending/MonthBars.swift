import Charts
import SpltCore
import SwiftUI

/// Your share month by month: one bar per month in shades of ink, with the chosen month in full ink
/// and named above the chart with its amount. Tapping a bar chooses it. The bars share the spending
/// charts' shape: 2pt corners and no baseline.
struct MonthBars: View {
    /// The first instant of each month, oldest first.
    let months: [Date]
    /// One amount per month, all in one currency.
    let amounts: [Money]

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var chosen: Date?

    static let chartHeight: CGFloat = 92

    var body: some View {
        let index = chosenIndex
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(monthName(months[safe: index]))
                    .font(.subheadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 8)
                Text(amountText(at: index))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Ink.secondary)
                    .contentTransition(.numericText(value: Double(amounts[safe: index]?.minorUnits ?? 0)))
            }
            .accessibilityElement(children: .combine)
            chart(chosen: index)
        }
        .padding(.vertical, 8)
        .onChange(of: months) { chosen = nil }
    }

    private func chart(chosen index: Int) -> some View {
        let values = amounts.map { max($0.minorUnits, 0) }
        let highest = max(values.max() ?? 0, 1)
        // the shortest bar still shows, as a 2pt stub, so an empty month reads as a month
        let stub = Double(highest) * 2 / Double(Self.chartHeight)
        let keys = months.map(key)
        return Chart {
            ForEach(Array(months.enumerated()), id: \.offset) { offset, month in
                BarMark(
                    x: .value("Month", keys[offset]),
                    y: .value("Your share", max(Double(values[safe: offset] ?? 0), stub)),
                    width: .ratio(0.78)
                )
                .cornerRadius(2)
                .foregroundStyle(offset == index ? Ink.text : Ink.tertiary)
                .accessibilityLabel(monthName(month))
                .accessibilityValue(amountText(at: offset))
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...Double(highest))
        .chartXScale(domain: keys)
        .chartXAxis {
            AxisMarks(values: keys) { value in
                AxisValueLabel(centered: true) {
                    if let key = value.as(String.self), let offset = keys.firstIndex(of: key) {
                        Text(axisLabel(offset))
                            .font(.caption2.weight(offset == index ? .semibold : .regular))
                            .foregroundStyle(offset == index ? Ink.text : Ink.secondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            // a tap, not a drag, so the list still scrolls when a swipe starts on the chart
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let plot = proxy.plotFrame else { return }
                        let x = tap.location.x - geometry[plot].origin.x
                        guard let key: String = proxy.value(atX: x), let offset = keys.firstIndex(of: key) else { return }
                        Motion.perform(Motion.quick) { chosen = months[offset] }
                    })
            }
        }
        .frame(height: Self.chartHeight + 20)
    }

    /// The chosen month, or the latest one.
    private var chosenIndex: Int {
        if let chosen, let offset = months.firstIndex(of: chosen) { return offset }
        return max(months.count - 1, 0)
    }

    private func key(_ month: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        return String(format: "%04ld-%02ld", parts.year ?? 0, parts.month ?? 0)
    }

    /// One letter per month. Past a year the bars are too narrow for that, so only January is
    /// labeled, with its year.
    private func axisLabel(_ offset: Int) -> String {
        let month = months[offset]
        if months.count <= 12 {
            return month.formatted(Date.FormatStyle(locale: locale, calendar: calendar).month(.narrow))
        }
        guard calendar.component(.month, from: month) == 1 || offset == 0 else { return "" }
        return month.formatted(Date.FormatStyle(locale: locale, calendar: calendar).year(.twoDigits))
    }

    private func monthName(_ month: Date?) -> String {
        guard let month else { return "" }
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        if calendar.isDate(month, equalTo: Date(), toGranularity: .year) {
            return month.formatted(style.month(.wide))
        }
        return month.formatted(style.month(.wide).year())
    }

    private func amountText(at index: Int) -> String {
        guard let money = amounts[safe: index] else { return "" }
        return MoneyFormatting.string(money, locale: locale, showsSign: money.minorUnits < 0)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if DEBUG
#Preview {
    let calendar = Calendar.current
    let now = Date()
    let months = SpendingRange.last12Months.months(now: now, earliest: nil, calendar: calendar)
    let values: [Int64] = [21_200, 15_500, 17_100, 20_800, 18_800, 24_000, 26_100, 74_210, 37_100, 19_600, 46_100, 30_300]
    return List {
        RaisedRows {
            MonthBars(months: months, amounts: values.map { Money(minorUnits: $0, currencyCode: "USD") })
        }
    }
    .listStyle(.plain)
    .paperBackground()
}
#endif
