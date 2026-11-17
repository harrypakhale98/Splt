import SpltCore
import SwiftUI
import WidgetKit

// MARK: Timeline

struct BalanceEntry: TimelineEntry {
    let date: Date
    /// Nil before the app has saved one, which happens the first time it opens after an update.
    var snapshot: BalanceWidgetSnapshot?
}

/// Reads what the app last saved. The app reloads the widget whenever that changes, so there is no schedule.
struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        Self.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(context.isPreview ? Self.sample : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> BalanceEntry {
        BalanceEntry(date: Date(), snapshot: BalanceWidgetSnapshot.load(from: PaymentInboxFile.sharedDefaults))
    }

    /// Made-up people and amounts for the widget gallery and previews.
    static let sample: BalanceEntry = {
        func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }
        func friend(_ name: String, _ initials: String, _ cents: Int64, _ color: BalanceWidgetSnapshot.PersonColor) -> BalanceWidgetSnapshot.Friend {
            .init(id: UUID(), name: name, balance: [usd(cents)], initials: initials, color: color)
        }
        // three of the app's person hues: plum, indigo, sienna
        return BalanceEntry(date: Date(), snapshot: BalanceWidgetSnapshot(
            owedToYou: [usd(14_250)], youOwe: [usd(3_800)],
            friends: [
                friend("Sam Rivera", "SR", 9_000, .init(lightFill: 0x96437F, lightText: 0xFFFFFF, darkFill: 0xDD9CCB, darkText: 0x0E0E12)),
                friend("Priya Nair", "PN", 5_250, .init(lightFill: 0x4B55A0, lightText: 0xFFFFFF, darkFill: 0xA3A9E8, darkText: 0x0E0E12)),
                friend("Jo Park", "JP", -3_800, .init(lightFill: 0xA85510, lightText: 0xFFFFFF, darkFill: 0xE3A26A, darkText: 0x0E0E12)),
            ],
            strip: [
                .init(lightFill: 0x96437F, lightText: 0xFFFFFF, darkFill: 0xDD9CCB, darkText: 0x0E0E12),
                .init(lightFill: 0x4B55A0, lightText: 0xFFFFFF, darkFill: 0xA3A9E8, darkText: 0x0E0E12),
                .init(lightFill: 0xA85510, lightText: 0xFFFFFF, darkFill: 0xE3A26A, darkText: 0x0E0E12),
            ]
        ))
    }()
}

// MARK: Widget

struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SpltWidgetKind.balance, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Your Balance")
        .description("Where you stand with friends, as on the Friends tab, and who you have the most money with.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct BalanceWidgetView: View {
    /// What the number covers, in the Friends tab hero's words.
    static let scope: LocalizedStringKey = "With friends"
    /// Shown in place of the balance before the app has saved one, and while the Face ID lock is on.
    static let hiddenNote: LocalizedStringKey = "Open Splt to see your balance."

    let entry: BalanceEntry
    @Environment(\.widgetFamily) private var family

    /// What can be shown: nothing before the app has saved, or while the Face ID lock is on.
    private var shown: BalanceWidgetSnapshot? {
        guard let snapshot = entry.snapshot, !snapshot.hidesDetails else { return nil }
        return snapshot
    }

    var body: some View {
        content
            .widgetURL(SpltWidgetKind.friendsURL)
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium { Ink.paper }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let shown {
                Text(inlineText(shown)).privacySensitive()
            } else {
                Text(Self.hiddenNote)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.scope)
                    .font(.caption)
                    .widgetAccentable()
                if let shown {
                    figure(shown, size: 22)
                        .privacySensitive()
                    if let others = otherAmounts(shown) {
                        Text("Also \(others)")
                            .font(.caption2)
                            .monospacedDigit()
                            .lineLimit(1)
                            .privacySensitive()
                    }
                } else {
                    Text(Self.hiddenNote)
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                // the rows already say who owes what, so the number stands with the strip instead of the sentence
                summary(heroSize: 34, withRows: !(shown?.friends.isEmpty ?? true))
                if let shown, !shown.friends.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(shown.friends.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 { Divider().overlay(Ink.hairline) }
                            FriendRow(friend: friend)
                        }
                        Spacer(minLength: 0)
                    }
                    // names come first: the big number shrinks a little before a name is cut short
                    .frame(maxWidth: 196, maxHeight: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                }
            }
        default:
            summary(heroSize: 34, withRows: false)
        }
    }

    /// The hero of the Friends tab, small: what it covers, one big number, then the quiet sentence, or
    /// beside the friend rows, the strip of who the money is between.
    private func summary(heroSize: CGFloat, withRows: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.scope)
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
            if let shown {
                Spacer(minLength: 0)
                figure(shown, size: heroSize)
                    .foregroundStyle(Ink.text)
                    .privacySensitive()
                if let others = otherAmounts(shown) {
                    Text("Also \(others)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                        .privacySensitive()
                }
                if withRows {
                    // right under the number, as under the Friends tab hero
                    if !shown.strip.isEmpty {
                        ShareStrip(colors: shown.strip.map { Ink.dynamic(light: $0.lightFill, dark: $0.darkFill) }, isGrooved: true)
                            .widgetAccentable()
                            .padding(.top, 6)
                    }
                } else {
                    Text(NetPosition.sentence(owedToYou: shown.owedToYou, youOwe: shown.youOwe))
                        .font(.caption)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(3)
                        .privacySensitive()
                }
            } else {
                Spacer(minLength: 0)
                Text(Self.hiddenNote)
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The signed figure, or "All settled up" in its place.
    @ViewBuilder
    private func figure(_ snapshot: BalanceWidgetSnapshot, size: CGFloat) -> some View {
        if let primary = snapshot.position.primary {
            Text(MoneyFormatting.string(primary, showsSign: true))
                .font(Typeface.hero(size: size))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
                .accessibilityLabel(MoneyFormatting.spokenBalance(primary))
        } else {
            Text(snapshot.position.settledTitle)
                .font(Typeface.hero(size: size * 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func otherAmounts(_ snapshot: BalanceWidgetSnapshot) -> String? {
        let others = snapshot.position.others
        guard !others.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: others.map { MoneyFormatting.string($0, showsSign: true) })
    }

    /// The hero's words, short: "You're owed $508.65".
    private func inlineText(_ snapshot: BalanceWidgetSnapshot) -> String {
        guard let primary = snapshot.position.primary else { return snapshot.position.settledTitle }
        let amount = MoneyFormatting.magnitudeString(primary)
        return primary.minorUnits > 0 ? String(localized: "You're owed \(amount)") : String(localized: "You owe \(amount)")
    }
}

/// A friend as the Friends tab lists them: their avatar, their name, and the amount in the colour of its
/// direction. The widget has no sections, so the Friends tab's caption under the name says which way it goes.
private struct FriendRow: View {
    let friend: BalanceWidgetSnapshot.Friend
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Link(destination: SpltWidgetKind.friendURL(friend.id)) {
            HStack(spacing: 8) {
                avatar
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    // the full name when it fits, else the first name, as the split bar and orbit shorten names
                    ViewThatFits(in: .horizontal) {
                        Text(friend.name)
                        Text(firstName)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    if let lead {
                        Text(caption(for: lead))
                            .font(.caption2)
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let lead {
                    Text(MoneyFormatting.magnitudeString(lead))
                        .font(Typeface.figure)
                        .foregroundStyle(Ink.direction(of: lead.minorUnits))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.vertical, 4)
            .privacySensitive()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    /// Initials on their person color, as `AvatarView` draws them. A tinted Home Screen paints the disc and
    /// its letters one color, so there the disc becomes a ring and the initials stay readable.
    @ViewBuilder
    private var avatar: some View {
        let initials = Text(friend.initials).font(.system(size: 9.6, weight: .medium))
        if renderingMode == .fullColor {
            Circle()
                .fill(Ink.dynamic(light: friend.color.lightFill, dark: friend.color.darkFill))
                .overlay { initials.foregroundStyle(Ink.dynamic(light: friend.color.lightText, dark: friend.color.darkText)) }
        } else {
            Circle()
                .strokeBorder(.secondary, lineWidth: 1)
                .overlay { initials }
        }
    }

    /// "Maya Chen" becomes "Maya".
    private var firstName: String {
        friend.name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? friend.name
    }

    /// The currency with the most money in it.
    private var lead: Money? {
        friend.balance.max { $0.minorUnits.magnitude < $1.minorUnits.magnitude }
    }

    /// The Friends tab's captions.
    private func caption(for money: Money) -> String {
        money.minorUnits > 0 ? String(localized: "owes you") : String(localized: "you owe")
    }

    /// As VoiceOver reads a Friends tab row: "Maya Chen, owes you $511.85".
    private var accessibilityText: String {
        let lines = friend.balance.map { money in
            let amount = MoneyFormatting.magnitudeString(money)
            return money.minorUnits > 0 ? String(localized: "owes you \(amount)") : String(localized: "you owe \(amount)")
        }
        return "\(friend.name), " + ListFormatter.localizedString(byJoining: lines)
    }
}

#Preview("Medium", as: .systemMedium) {
    BalanceWidget()
} timeline: {
    BalanceProvider.sample
    BalanceEntry(date: Date(), snapshot: BalanceWidgetSnapshot())
    BalanceEntry(date: Date(), snapshot: .hidden)
}
