import SpltCore
import SwiftUI

/// The top of a group: its colors, name, people, your balance in big numerals and the Settle Up button.
struct GroupHeroSection: View {
    let group: SplitGroup
    let members: [Person]
    let totals: BalanceTotals
    let canSettle: Bool
    let onSettleUp: () -> Void
    /// 0 while the hero is fully on screen, 1 once it has scrolled up into the navigation bar.
    var condense: Double = 0
    /// A slim header for the Balances and Totals screens, so the content below stays above the fold.
    var compact = false
    /// Whether the slim header repeats your balance. The orbit already shows it on Balances.
    var showsAmount = true

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            Group {
                if compact { compactContent } else { fullContent }
            }
            .padding(compact ? 16 : 20)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { GroupHeroBackground(group: group) }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.separator.opacity(0.5))
            }
            .opacity(1 - condense * 0.65)
            .scaleEffect(1 - condense * 0.05, anchor: .top)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var fullContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            identity
            balance
            Button(action: onSettleUp) {
                Text("Settle Up")
                    .font(.headline)
                    .foregroundStyle(PersonPalette.onColor)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canSettle)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(group.name)
                    .font(.title3.weight(.bold))
                    .fontDesign(.serif)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if !typeSize.isAccessibilitySize {
                    AvatarStack(members, members: group.memberIDs, size: 24, limit: 4)
                }
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 8))
            layout {
                if showsAmount {
                    compactBalance
                } else {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineLimit(2)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Button(action: onSettleUp) {
                    Text("Settle Up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PersonPalette.onColor)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .disabled(!canSettle)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var compactBalance: some View {
        if totals.isSettled {
            Label("You are all settled up", systemImage: "checkmark.circle.fill")
                .font(.headline)
        } else {
            let line = totals.owedToYou.first.map { ($0, Int64(1)) } ?? totals.youOwe.first.map { ($0, Int64(-1)) }
            if let (amount, sign) = line {
                let money = Money(minorUnits: amount.minorUnits * sign, currencyCode: amount.currencyCode)
                VStack(alignment: .leading, spacing: 0) {
                    Text(sign > 0 ? "You are owed" : "You owe")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(MoneyFormatting.string(money, locale: locale, showsSign: true))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: Double(money.minorUnits)))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: group.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Spacer()
                if !typeSize.isAccessibilitySize {
                    AvatarStack(members, members: group.memberIDs, size: 32, limit: 5)
                }
            }
            Text(group.name)
                .font(.largeTitle.weight(.bold))
                .fontDesign(.serif)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let count = members.count
        let people = String(AttributedString(localized: "^[\(count) person](inflect: true)").characters)
        if let start = group.tripStart, let end = group.tripEnd {
            let range = (start..<max(end, start.addingTimeInterval(1))).formatted(.interval.day().month(.abbreviated).locale(locale))
            return "\(range) · \(people)"
        }
        return "\(group.currencyCode) · \(people)"
    }

    @ViewBuilder
    private var balance: some View {
        if totals.isSettled {
            Label("You are all settled up", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(totals.owedToYou, id: \.currencyCode) { amount in
                    line("You are owed", money: amount, sign: 1)
                }
                ForEach(totals.youOwe, id: \.currencyCode) { amount in
                    line("You owe", money: amount, sign: -1)
                }
            }
        }
    }

    private func line(_ caption: LocalizedStringKey, money: Money, sign: Int64) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HeroAmount(Money(minorUnits: money.minorUnits * sign, currencyCode: money.currencyCode))
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Owed") {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.kind == .trip }) ?? nil
    let members = trip.flatMap { try? services.people.people(ids: $0.memberIDs) } ?? []
    List {
        if let trip {
            GroupHeroSection(
                group: trip, members: members,
                totals: BalanceTotals(owedToYou: [Money(minorUnits: 21_460, currencyCode: "EUR")], youOwe: []),
                canSettle: true, onSettleUp: {}
            )
        }
    }
}
#endif
