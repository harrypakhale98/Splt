import SpltCore
import SwiftUI

/// The top of a spending screen: the range menu, then "Your share · last 12 months" over the one big
/// figure, then whatever lines the screen puts under it.
struct SpendingHero<Lines: View>: View {
    @Binding var range: SpendingRange
    let share: Money
    @ViewBuilder var lines: Lines

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpendingRangeMenu(range: $range)
                .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your share · \(range.phrase)")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                // refunds can outweigh spending, and then the figure keeps its minus sign
                HeroAmount(share, showsSign: share.minorUnits < 0)
            }
            .accessibilityElement(children: .combine)
            lines
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// The small pill above the figure that sets the period for the whole screen.
struct SpendingRangeMenu: View {
    @Binding var range: SpendingRange

    var body: some View {
        Menu {
            Picker("Period", selection: $range) {
                ForEach(SpendingRange.menu) { Text($0.title).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(range.title)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Ink.text)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(Ink.secondary)
        .accessibilityLabel("Period")
        .accessibilityValue(range.title)
    }
}
