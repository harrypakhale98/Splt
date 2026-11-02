import Charts
import SpltCore
import SwiftUI

private struct RecapTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// A big rounded number that rolls up from zero when its page comes into view.
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
            .font(.system(size: min(size * scale, size * 1.4), weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText(value: Double(shown.minorUnits)))
            .animation(reduceMotion ? nil : .smooth(duration: 1.0), value: active)
            .accessibilityLabel(hidden ? String(localized: "Amount hidden") : MoneyFormatting.magnitudeString(money, locale: locale))
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
            Spacer()
            Image(systemName: group.symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(group.name)
                .font(.largeTitle.weight(.bold))
                .fontDesign(.serif)
                .minimumScaleFactor(0.6)
            RecapTitle(text: "You spent together")
            RecapNumber(money: stats.total, hidden: hidesAmounts, active: active, size: 68)
            Text("^[\(stats.expenseCount) expense](inflect: true) over ^[\(stats.dayCount) \(stats.bucket == .day ? "day" : "month")](inflect: true)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            RecapTitle(text: stats.bucket == .day ? "Day by day" : "Month by month")
            Chart(stats.slices) { slice in
                BarMark(
                    x: .value("Date", slice.start, unit: stats.bucket == .day ? .day : .month),
                    y: .value("Spent", active || reduceMotion ? chartValue(slice.total) : 0)
                )
                .cornerRadius(5)
                .foregroundStyle(slice == stats.busiest ? Color.accentColor : Color.accentColor.opacity(0.35))
                .accessibilityLabel(slice.start.formatted(.dateTime.month().day()))
                .accessibilityValue(recapAmount(slice.total, hidden: hidesAmounts, locale: locale))
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: stats.bucket == .day ? .dateTime.day() : .dateTime.month(.narrow))
                }
            }
            .chartYScale(domain: 0...(max(stats.slices.map { chartValue($0.total) }.max() ?? 1, 1) * 1.1))
            .frame(height: 220)
            .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: active)
            if let busiest = stats.busiest {
                Text("Busiest \(stats.bucket == .day ? "day" : "month"): \(busiest.start.formatted(stats.bucket == .day ? .dateTime.weekday(.abbreviated).month(.abbreviated).day() : .dateTime.month(.wide))), \(recapAmount(busiest.total, hidden: hidesAmounts, locale: locale))")
                    .font(.headline)
            }
            Text("About \(recapAmount(stats.average, hidden: hidesAmounts, locale: locale)) a \(stats.bucket == .day ? "day" : "month") on average")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartValue(_ money: Money) -> Double {
        NSDecimalNumber(decimal: money.decimalValue).doubleValue
    }
}

struct RecapBiggestPage: View {
    let stats: RecapStats
    let hidesAmounts: Bool
    let active: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        if let biggest = stats.biggest {
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                RecapTitle(text: "The biggest one")
                Image(systemName: biggest.category.symbolName)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .frame(width: 88, height: 88)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityHidden(true)
                Text(biggest.title)
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.serif)
                    .minimumScaleFactor(0.6)
                    .lineLimit(3)
                RecapNumber(money: biggest.amount, hidden: hidesAmounts, active: active, size: 52)
                Text(detail(biggest))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Spacer()
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
            let color = PersonPalette.color(for: payer.id, in: members)
            VStack(spacing: 18) {
                Spacer()
                RecapTitle(text: "Who paid the most")
                ZStack {
                    Circle().stroke(color.opacity(0.18), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: active || reduceMotion ? min(CGFloat(payer.percent) / 100, 1) : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .smooth(duration: 1.0), value: active)
                    AvatarView(name: payer.name, id: payer.id, members: members, size: 96)
                }
                .frame(width: 190, height: 190)
                .accessibilityHidden(true)
                Text(payer.name)
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.serif)
                Text("covered \(payer.percent)% of the bills")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(recapAmount(payer.paid, hidden: hidesAmounts, locale: locale))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
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
        PersonPalette.color(at: [5, 7, 1, 10, 3][index % 5])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            RecapTitle(text: "Where it went")
            Chart(Array(stats.categories.enumerated()), id: \.element.id) { index, share in
                SectorMark(
                    angle: .value("Share", active || reduceMotion ? Double(share.amount.minorUnits) : 0.0001),
                    innerRadius: .ratio(0.62),
                    angularInset: 2
                )
                .cornerRadius(6)
                .foregroundStyle(color(at: index))
                .accessibilityLabel(share.category.title)
                .accessibilityValue("\(share.percent)%")
            }
            .frame(height: 210)
            .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: active)
            VStack(spacing: 10) {
                ForEach(Array(stats.categories.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 10) {
                        Circle().fill(color(at: index)).frame(width: 12, height: 12)
                        Label(share.category.title, systemImage: share.category.symbolName)
                            .font(.body)
                        Spacer()
                        Text("\(share.percent)%")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                        if !hidesAmounts {
                            Text(MoneyFormatting.string(share.amount, locale: locale))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer()
            Spacer()
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
            Spacer()
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(summary ?? String(localized: "That is the story of \(group.name)."))
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.serif)
                .minimumScaleFactor(0.6)
                .opacity(active || reduceMotion ? 1 : 0)
                .offset(y: active || reduceMotion ? 0 : 12)
                .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: active)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack {
                Image(systemName: group.symbol)
                Text(group.name)
                    .fontDesign(.serif)
                Spacer()
            }
            .font(.title2.weight(.bold))
            Text(recapAmount(stats.total, hidden: hidesAmounts))
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("^[\(stats.expenseCount) expense](inflect: true) over ^[\(stats.dayCount) \(stats.bucket == .day ? "day" : "month")](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart(stats.slices) { slice in
                BarMark(
                    x: .value("Date", slice.start, unit: stats.bucket == .day ? .day : .month),
                    y: .value("Spent", NSDecimalNumber(decimal: slice.total.decimalValue).doubleValue)
                )
                .cornerRadius(3)
                .foregroundStyle(slice == stats.busiest ? Color.accentColor : Color.accentColor.opacity(0.35))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 90)
            VStack(alignment: .leading, spacing: 6) {
                if let top = stats.categories.first {
                    Label("\(top.category.title), \(top.percent)%", systemImage: top.category.symbolName)
                }
                if let payer = stats.topPayer {
                    Label("\(payer.name) paid \(payer.percent)%", systemImage: "creditcard")
                }
                if let biggest = stats.biggest {
                    Label("Biggest: \(biggest.title)", systemImage: "star")
                }
            }
            .font(.subheadline)
            if let summary {
                Text(summary)
                    .font(.callout)
                    .fontDesign(.serif)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Splt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 340, height: 440, alignment: .topLeading)
        .background(Color.white)
        .overlay(alignment: .top) {
            GroupGradient(members: group.memberIDs).frame(height: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
