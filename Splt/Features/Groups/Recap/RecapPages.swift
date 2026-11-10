import Accessibility
import Charts
import SpltCore
import SwiftUI

private struct RecapTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A big serif number that rolls up from zero when its page comes into view.
private struct RecapNumber: View {
    let money: Money
    let hidden: Bool
    let active: Bool
    var size: CGFloat = 64

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        let shown = (active || reduceMotion) ? money : Money.zero(currencyCode: money.currencyCode)
        Text(recapAmount(shown, hidden: hidden, locale: locale))
            .font(Typeface.hero(size: min(size * scale, size * 1.4)))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText(value: Double(shown.minorUnits)))
            .motion(Motion.reveal, value: active)
            .accessibilityLabel(recapSpokenAmount(money, hidden: hidden, locale: locale))
    }
}

struct RecapTotalPage: View {
    let group: SplitGroup
    let stats: RecapStats
    let hidesAmounts: Bool
    let active: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(group.name)
                .font(.system(.largeTitle, design: .serif))
                .minimumScaleFactor(0.6)
            RecapTitle(text: "You spent together")
            RecapNumber(money: stats.total, hidden: hidesAmounts, active: active, size: 68)
            Text(recapSpan(stats))
                .font(.headline)
                .foregroundStyle(Ink.secondary)
            if let leftOut = recapLeftOutLine(stats, hidden: hidesAmounts, locale: locale) {
                Text(leftOut)
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct RecapDaysPage: View {
    let stats: RecapStats
    let hidesAmounts: Bool
    let active: Bool

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let labels = axisLabels
        VStack(alignment: .leading, spacing: 16) {
            RecapTitle(text: stats.bucket == .day ? "Day by day" : "Month by month")
            Chart(stats.slices) { slice in
                BarMark(
                    x: .value("Date", slice.start, unit: stats.bucket == .day ? .day : .month),
                    y: .value("Spent", active || reduceMotion ? RecapStats.chartValue(slice.total) : 0)
                )
                .cornerRadius(1)
                .foregroundStyle(slice == stats.busiest ? Ink.text : Ink.tertiary)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: stats.axisDates) { value in
                    AxisValueLabel {
                        Text(value.as(Date.self).flatMap { labels[$0] } ?? "")
                    }
                }
            }
            .chartYScale(domain: stats.chartDomain)
            .frame(height: 220)
            .motion(Motion.reveal, value: active)
            // one stop for the whole chart, with Audio Graphs for the bars themselves
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stats.bucket == .day ? Text("Spending by day") : Text("Spending by month"))
            .accessibilityValue(accessibilitySummary)
            .accessibilityChartDescriptor(
                RecapSlicesChartDescriptor(stats: stats, hidesAmounts: hidesAmounts, locale: locale)
            )
            if let busiest = stats.busiest {
                Text(busiestLine(busiest))
                    .font(.headline)
                    .accessibilityHidden(true)
            }
            Text(averageLine)
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Day numbers along the axis, with the month on the first one and wherever the month changes,
    /// so a trip across two months reads "Mar 28, 31, Apr 4" rather than "28 31 4".
    private var axisLabels: [Date: String] {
        var labels: [Date: String] = [:]
        var previous: Date?
        for date in stats.axisDates {
            if stats.bucket == .month {
                let newYear = previous.map { !calendar.isDate($0, equalTo: date, toGranularity: .year) } ?? false
                labels[date] = newYear
                    ? date.formatted(.dateTime.month(.abbreviated).year(.twoDigits).locale(locale))
                    : date.formatted(.dateTime.month(.narrow).locale(locale))
            } else {
                let newMonth = previous.map { !calendar.isDate($0, equalTo: date, toGranularity: .month) } ?? true
                labels[date] = newMonth
                    ? date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
                    : date.formatted(.dateTime.day().locale(locale))
            }
            previous = date
        }
        return labels
    }

    private var accessibilitySummary: String {
        [stats.busiest.map(busiestLine), averageLine].compactMap { $0 }.joined(separator: ". ")
    }

    // one whole sentence per bucket, so each can be translated with its own grammar
    private func busiestLine(_ busiest: RecapStats.Slice) -> String {
        let amount = recapAmount(busiest.total, hidden: hidesAmounts, locale: locale)
        if stats.bucket == .day {
            let date = busiest.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale))
            return String(localized: "Busiest day: \(date), \(amount)")
        }
        let date = busiest.start.formatted(.dateTime.month(.wide).locale(locale))
        return String(localized: "Busiest month: \(date), \(amount)")
    }

    private var averageLine: String {
        let amount = recapAmount(stats.average, hidden: hidesAmounts, locale: locale)
        if stats.bucket == .day { return String(localized: "About \(amount) a day on average") }
        return String(localized: "About \(amount) a month on average")
    }
}

/// The day or month bars for Audio Graphs: one point per slice, named by its day or its month.
private struct RecapSlicesChartDescriptor: AXChartDescriptorRepresentable {
    let stats: RecapStats
    let hidesAmounts: Bool
    let locale: Locale

    func makeChartDescriptor() -> AXChartDescriptor {
        let byDay = stats.bucket == .day
        let names = stats.slices.map { slice in
            byDay
                ? slice.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale))
                : slice.start.formatted(.dateTime.month(.wide).year().locale(locale))
        }
        let code = stats.currencyCode
        let hidden = hidesAmounts
        let numberLocale = locale
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: byDay ? String(localized: "Day") : String(localized: "Month"), categoryOrder: names
        )
        let yAxis = AXNumericDataAxisDescriptor(title: String(localized: "Spent"), range: stats.chartDomain, gridlinePositions: []) { value in
            hidden ? String(localized: "Amount hidden") : value.formatted(.currency(code: code).locale(numberLocale))
        }
        let points = zip(names, stats.slices).map { name, slice in
            AXDataPoint(x: name, y: RecapStats.chartValue(slice.total))
        }
        return AXChartDescriptor(
            title: byDay ? String(localized: "Spending by day") : String(localized: "Spending by month"),
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: String(localized: "Spent"), isContinuous: false, dataPoints: points)]
        )
    }
}

/// How many expenses over how many days or months, each bucket its own sentence with its own plural.
func recapSpan(_ stats: RecapStats) -> LocalizedStringKey {
    if stats.bucket == .day {
        return "^[\(stats.expenseCount) expense](inflect: true) over ^[\(stats.dayCount) day](inflect: true)"
    }
    return "^[\(stats.expenseCount) expense](inflect: true) over ^[\(stats.dayCount) month](inflect: true)"
}

struct RecapBiggestPage: View {
    let stats: RecapStats
    let hidesAmounts: Bool
    let active: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        if let biggest = stats.biggest {
            VStack(alignment: .leading, spacing: 14) {
                RecapTitle(text: "The biggest one")
                Text(biggest.title)
                    .font(.system(.largeTitle, design: .serif))
                    .minimumScaleFactor(0.6)
                    .lineLimit(3)
                RecapNumber(money: biggest.amount, hidden: hidesAmounts, active: active, size: 52)
                Text(detail(biggest))
                    .font(.headline)
                    .foregroundStyle(Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func detail(_ biggest: RecapStats.Biggest) -> String {
        let date = biggest.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        guard let payer = biggest.payerName else { return date }
        return String(localized: "Paid by \(payer) on \(date)")
    }
}

struct RecapPayerPage: View {
    let stats: RecapStats
    let members: [PersonID]
    let hidesAmounts: Bool
    let active: Bool

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let payer = stats.topPayer {
            let everyone = payer.everyone
            let tied = everyone.count > 1
            // each person's share of the bar, so a tie shows as two equal parts in their own colours
            let share = min(CGFloat(payer.percent) / 100, 1 / CGFloat(everyone.count))
            // the percent sign goes through the locale, "50 %" in some regions
            let percent = payer.percent.formatted(.percent.locale(locale))
            VStack(alignment: .leading, spacing: 14) {
                RecapTitle(text: "Who paid the most")
                HStack(spacing: 8) {
                    ForEach(everyone, id: \.id) { person in
                        AvatarView(name: person.name, id: person.id, members: members, size: 56)
                    }
                }
                .accessibilityHidden(true)
                Text(recapPayerNames(payer, locale: locale))
                    .font(.system(.largeTitle, design: .serif))
                    .minimumScaleFactor(0.6)
                Group {
                    if tied {
                        Text("split it, covering \(percent) of the bills each")
                    } else {
                        Text("covered \(percent) of the bills")
                    }
                }
                .font(.title3)
                .foregroundStyle(Ink.secondary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Ink.hairline)
                        HStack(spacing: 0) {
                            ForEach(everyone, id: \.id) { person in
                                Rectangle()
                                    .fill(PersonPalette.color(for: person.id, in: members))
                                    .frame(width: proxy.size.width * (active || reduceMotion ? share : 0))
                            }
                        }
                        .motion(Motion.reveal, value: active)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                Text(tied ? String(localized: "\(recapAmount(payer.paid, hidden: hidesAmounts, locale: locale)) each")
                     : recapAmount(payer.paid, hidden: hidesAmounts, locale: locale))
                    .font(Typeface.figure)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct RecapCategoriesPage: View {
    let stats: RecapStats
    let hidesAmounts: Bool
    let active: Bool

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func color(at index: Int) -> Color {
        Ink.text.opacity([1, 0.7, 0.5, 0.35, 0.2][index % 5])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RecapTitle(text: "Where it went")
            Chart(Array(stats.categories.enumerated()), id: \.element.id) { index, share in
                SectorMark(
                    angle: .value("Share", active || reduceMotion ? Double(share.amount.minorUnits) : 0.0001),
                    innerRadius: .ratio(0.62),
                    angularInset: 1
                )
                .cornerRadius(0)
                .foregroundStyle(color(at: index))
                .accessibilityLabel(share.category.title)
                .accessibilityValue(share.percent.formatted(.percent.locale(locale)))
            }
            .frame(height: 210)
            .motion(Motion.reveal, value: active)
            VStack(spacing: 10) {
                ForEach(Array(stats.categories.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 10) {
                        Circle().fill(color(at: index)).frame(width: 12, height: 12)
                        Label(share.category.title, systemImage: share.category.symbolName)
                            .font(.body)
                        Spacer(minLength: 4)
                        Text(share.percent.formatted(.percent.locale(locale)))
                            .font(.body)
                            .monospacedDigit()
                        if !hidesAmounts {
                            Text(MoneyFormatting.string(share.amount, locale: locale))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecapSummaryPage: View {
    let group: SplitGroup
    let stats: RecapStats
    let summary: String?
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                if let summary {
                    Text(summary)
                } else {
                    Text(facts)
                }
            }
            .font(.system(.largeTitle, design: .serif))
            .minimumScaleFactor(0.6)
            .opacity(active || reduceMotion ? 1 : 0)
            .offset(y: active || reduceMotion ? 0 : 12)
            .motion(Motion.reveal, value: active)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A plain line of counts, for when the on-device summary has nothing to say.
    private var facts: LocalizedStringKey {
        let people = group.memberIDs.count
        if stats.bucket == .day {
            return "^[\(people) person](inflect: true), ^[\(stats.expenseCount) expense](inflect: true), ^[\(stats.dayCount) day](inflect: true)."
        }
        return "^[\(people) person](inflect: true), ^[\(stats.expenseCount) expense](inflect: true), ^[\(stats.dayCount) month](inflect: true)."
    }
}

/// The picture people share: the highlights on one card, with amounts left out on request.
struct RecapShareCard: View {
    let group: SplitGroup
    let stats: RecapStats
    let summary: String?
    let hidesAmounts: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(group.name)
                .font(Typeface.title)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(recapAmount(stats.total, hidden: hidesAmounts))
                .font(Typeface.hero(size: 54))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(recapSpan(stats))
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let leftOut = recapLeftOutLine(stats, hidden: hidesAmounts, locale: .current) {
                Text(leftOut)
                    .font(.caption)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(2)
            }
            Chart(stats.slices) { slice in
                BarMark(
                    x: .value("Date", slice.start, unit: stats.bucket == .day ? .day : .month),
                    y: .value("Spent", RecapStats.chartValue(slice.total))
                )
                .cornerRadius(1)
                .foregroundStyle(slice == stats.busiest ? Ink.text : Ink.tertiary)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: stats.chartDomain)
            .frame(height: 90)
            // plain ledger rows: what on the left, the figure on the right
            VStack(alignment: .leading, spacing: 6) {
                if let top = stats.categories.first {
                    ledgerRow(Text(top.category.title), figure: top.percent.formatted(.percent))
                }
                if let payer = stats.topPayer {
                    let names = recapPayerNames(payer, locale: .current)
                    let percent = payer.percent.formatted(.percent)
                    ledgerRow(
                        Text("Paid by \(names)"),
                        figure: payer.tiedWith.isEmpty ? percent : String(localized: "\(percent) each")
                    )
                }
                if let biggest = stats.biggest {
                    ledgerRow(Text("Biggest: \(biggest.title)"), figure: recapAmount(biggest.amount, hidden: hidesAmounts))
                }
            }
            .font(.subheadline)
            if let summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            // the mark keeps its line even when everything above is long
            Text("Splt")
                .font(.caption)
                .foregroundStyle(Ink.secondary)
                .layoutPriority(1)
        }
        .padding(24)
        .frame(width: 340, height: 440, alignment: .topLeading)
        .background(Ink.paper)
        .overlay(alignment: .top) {
            ShareStrip(people: group.memberIDs, members: group.memberIDs, height: 8)
        }
    }

    private func ledgerRow(_ label: Text, figure: String) -> some View {
        HStack(spacing: 8) {
            label
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(figure)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}

/// The top payer's name, or everyone who shares the top spot: "Ana and Ben".
func recapPayerNames(_ payer: RecapStats.TopPayer, locale: Locale) -> String {
    payer.everyone.map(\.name).formatted(.list(type: .and).locale(locale))
}

/// One quiet line naming the spending in other currencies that the recap leaves out, or nil.
func recapLeftOutLine(_ stats: RecapStats, hidden: Bool, locale: Locale) -> String? {
    guard !stats.leftOut.isEmpty else { return nil }
    if hidden {
        let codes = stats.leftOut.map(\.currencyCode).formatted(.list(type: .and).locale(locale))
        return String(localized: "Doesn't include spending in \(codes).")
    }
    if stats.leftOut.count == 1, let only = stats.leftOut.first {
        return String(localized: "Doesn't include \(recapAmount(only, hidden: false, locale: locale)) in \(only.currencyCode).")
    }
    let amounts = stats.leftOut.map { recapAmount($0, hidden: false, locale: locale) }.formatted(.list(type: .and).locale(locale))
    return String(localized: "Doesn't include \(amounts) in other currencies.")
}
