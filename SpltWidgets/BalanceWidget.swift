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
        return BalanceEntry(date: Date(), snapshot: BalanceWidgetSnapshot(
            owedToYou: [usd(14_250)], youOwe: [usd(3_800)],
            friends: [
                .init(id: UUID(), name: "Sam Rivera", balance: [usd(9_000)]),
                .init(id: UUID(), name: "Priya Nair", balance: [usd(5_250)]),
                .init(id: UUID(), name: "Jo Park", balance: [usd(-3_800)]),
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
        .description("Where you stand with everyone, and who owes whom.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct BalanceWidgetView: View {
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
                Text("Your balance")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Your balance")
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
                    Text("Open Splt to see it.")
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                summary(heroSize: 34)
                if let shown, !shown.friends.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(shown.friends.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 { Divider().overlay(Ink.hairline) }
                            FriendRow(friend: friend)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        default:
            summary(heroSize: 34)
        }
    }

    /// The hero of the Friends tab, small: what it covers, one big number, and the quiet sentence.
    private func summary(heroSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your balance")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
            Spacer(minLength: 0)
            if let shown {
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
                Text(NetPosition.sentence(owedToYou: shown.owedToYou, youOwe: shown.youOwe))
                    .font(.caption)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(3)
                    .privacySensitive()
            } else {
                Text("Open Splt to see your balance.")
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
            Text("All settled up")
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

    private func inlineText(_ snapshot: BalanceWidgetSnapshot) -> String {
        snapshot.position.primary.map { MoneyFormatting.spokenBalance($0) } ?? String(localized: "All settled up")
    }
}

/// A friend and where you stand with them, as on the Friends tab: the amount in the colour of its direction.
private struct FriendRow: View {
    let friend: BalanceWidgetSnapshot.Friend

    var body: some View {
        Link(destination: SpltWidgetKind.friendURL(friend.id)) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(friend.name)
                        .font(.subheadline)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    Text(direction)
                        .font(.caption)
                        .foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 4)
                if let lead {
                    Text(MoneyFormatting.string(lead, showsSign: true))
                        .font(Typeface.figure)
                        .foregroundStyle(Ink.direction(of: lead.minorUnits))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.vertical, 6)
            .privacySensitive()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    /// The currency with the most money in it.
    private var lead: Money? {
        friend.balance.max { $0.minorUnits.magnitude < $1.minorUnits.magnitude }
    }

    /// The Friends tab's section names.
    private var direction: String {
        let owes = friend.balance.contains { $0.minorUnits > 0 }
        let owed = friend.balance.contains { $0.minorUnits < 0 }
        switch (owes, owed) {
        case (true, true): return String(localized: "Both ways")
        case (true, false): return String(localized: "Owes you")
        case (false, true): return String(localized: "You owe")
        case (false, false): return String(localized: "Settled up")
        }
    }

    private var accessibilityText: String {
        let amounts = friend.balance.map { MoneyFormatting.spokenBalance($0) }
        return "\(friend.name), " + ListFormatter.localizedString(byJoining: amounts)
    }
}

#Preview("Medium", as: .systemMedium) {
    BalanceWidget()
} timeline: {
    BalanceProvider.sample
    BalanceEntry(date: Date(), snapshot: BalanceWidgetSnapshot())
    BalanceEntry(date: Date(), snapshot: .hidden)
}
