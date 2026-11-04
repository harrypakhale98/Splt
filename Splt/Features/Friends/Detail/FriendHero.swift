import SpltCore
import SwiftUI

/// The top of a friend's screen: their color mesh, the groups you share as small glyphs in orbit
/// around them, the net balance in big numerals and the one thing to do next.
struct FriendHero: View {
    let friend: Person
    let balance: [Money]
    let sharedGroups: [SplitGroup]
    let primary: Action
    let secondary: Action?

    struct Action {
        var title: LocalizedStringKey
        var symbol: String
        /// Spoken when the visible title is shortened to fit.
        var spokenTitle: LocalizedStringKey?
        var run: () -> Void
    }

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var color: Color { PersonPalette.color(for: friend.id) }

    private var position: NetPosition {
        NetPosition(totals: BalanceTotals(amounts: balance))
    }

    var body: some View {
        VStack(spacing: 14) {
            orbit
            VStack(spacing: 4) {
                Text(friend.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if friend.isPlaceholder {
                    Text("Not on Splt yet")
                        .font(.footnote)
                        .foregroundStyle(.legibleOnTint)
                }
            }
            figure
            actions
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                GroupGradient(colors: [color, color.mix(with: .teal, by: 0.35), color.mix(with: .white, by: 0.3)])
                    .opacity(0.8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Orbit

    @ViewBuilder
    private var orbit: some View {
        let groups = Array(sharedGroups.prefix(6))
        let side: CGFloat = typeSize.isAccessibilitySize ? 200 : 148
        let glyph: CGFloat = 30
        let radius = (side - glyph) / 2
        ZStack {
            if !groups.isEmpty {
                Circle()
                    .strokeBorder(color.opacity(0.35), lineWidth: 1.5)
                    .padding(glyph / 2)
            }
            AvatarView(person: friend, size: 68)
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                let angle = Angle.degrees(-90 + 360 * Double(index) / Double(groups.count) + 20)
                GroupGlyph(symbol: group.symbol, members: group.memberIDs, size: glyph)
                    .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(orbitLabel)
    }

    private var orbitLabel: String {
        guard !sharedGroups.isEmpty else { return friend.name }
        let names = ListFormatter.localizedString(byJoining: sharedGroups.map(\.name))
        return String(localized: "\(friend.name), shared groups: \(names)")
    }

    // MARK: Balance

    @ViewBuilder
    private var figure: some View {
        VStack(spacing: 4) {
            if let amount = position.primary {
                HeroAmount(amount)
                Text(sentence(for: amount))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.legibleOnTint)
                if !position.others.isEmpty {
                    Text("Also \(otherAmounts)")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.legibleOnTint)
                        .accessibilityLabel(Text("Also \(spokenOthers)"))
                }
            } else {
                Text("All Square")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Nothing owed between you and \(ReminderMessage.firstName(friend.name)).")
                    .font(.subheadline)
                    .foregroundStyle(.legibleOnTint)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sentence(for amount: Money) -> String {
        let first = ReminderMessage.firstName(friend.name)
        return amount.isPositive
            ? String(localized: "\(first) owes you")
            : String(localized: "You owe \(first)")
    }

    private var otherAmounts: String {
        ListFormatter.localizedString(
            byJoining: position.others.map { MoneyFormatting.string($0, locale: locale, showsSign: true) }
        )
    }

    private var spokenOthers: String {
        ListFormatter.localizedString(byJoining: position.others.map { MoneyLabel.spokenBalance($0, locale: locale) })
    }

    // MARK: Actions

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(spacing: 10) { buttons }
        }
        .controlSize(.large)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: primary.run) {
            HStack(spacing: 8) {
                Image(systemName: primary.symbol)
                Text(primary.title).fixedSize(horizontal: true, vertical: false)
            }
            .font(.headline)
            .foregroundStyle(PersonPalette.onColor)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        if let secondary {
            Button(action: secondary.run) {
                HStack(spacing: 8) {
                    Image(systemName: secondary.symbol)
                    Text(secondary.title).fixedSize(horizontal: true, vertical: false)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(secondary.spokenTitle ?? secondary.title)
        }
    }
}
