import Charts
import SpltCore
import SwiftUI

/// A small version of the recap that opens it: the group's colors, two big numbers and a sparkline.
struct RecapEntryCard: View {
    let group: SplitGroup
    let stats: RecapStats
    let members: [Person]
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(group.kind == .trip ? "Trip Recap" : "Recap", systemImage: "sparkles.rectangle.stack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.7))
                    Spacer()
                    if !typeSize.isAccessibilitySize {
                        AvatarStack(members, members: group.memberIDs, size: 24, limit: 4)
                    }
                }
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .bottom, spacing: 14))
                layout {
                    number("Total spent", stats.total, size: .title2)
                    number(stats.bucket == .day ? "Per day" : "Per month", stats.average, size: .headline)
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: 4)
                        sparkline
                    }
                }
                Button(action: onOpen) {
                    Label("Watch the Recap", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(PersonPalette.onColor)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(18)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .background { GroupHeroBackground(group: group) }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.separator.opacity(0.5))
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func number(_ title: LocalizedStringKey, _ money: Money, size: Font.TextStyle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.7))
            Text(MoneyFormatting.string(money, locale: locale))
                .font(.system(size, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }

    private var sparkline: some View {
        Chart(stats.slices) { slice in
            BarMark(
                x: .value("Date", slice.start, unit: stats.bucket == .day ? .day : .month),
                y: .value("Spent", NSDecimalNumber(decimal: slice.total.decimalValue).doubleValue)
            )
            .cornerRadius(2)
            .foregroundStyle(slice == stats.busiest ? Color.accentColor : Color.primary.opacity(0.35))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(width: 64, height: 40)
        .accessibilityHidden(true)
    }
}
