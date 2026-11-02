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

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
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
            .padding(20)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { GroupGradient(members: group.memberIDs) }
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
