import SpltCore
import SwiftUI
import WidgetKit

// MARK: Timeline

struct ToSplitEntry: TimelineEntry {
    let date: Date
    let count: Int
    /// Newest first, as many as any size can show.
    var payments: [PendingPayment] = []
    /// A trip that ended lately, offered first as in the app.
    var wrapUp: ToSplitSnapshot.WrapUp?
    /// The Face ID lock is on: the count only, never what was bought.
    var hidesDetails = false
}

/// Works out what waits from the inbox file, using what the app last decided about each payment.
/// The timeline steps on as payments turn a week old and wrap-ups end, so it stays right while the app is closed.
struct ToSplitProvider: TimelineProvider {
    static let mostShown = 4

    func placeholder(in context: Context) -> ToSplitEntry {
        Self.sample()
    }

    /// Made-up payments for the widget gallery and previews.
    static func sample(now: Date = Date()) -> ToSplitEntry {
        func sample(_ merchant: String, _ minorUnits: Int64, hoursAgo: Double, _ source: PendingPayment.Source) -> PendingPayment {
            PendingPayment(
                id: UUID(), merchant: merchant, amount: Money(minorUnits: minorUnits, currencyCode: "USD"),
                date: now.addingTimeInterval(-hoursAgo * 3_600), source: source
            )
        }
        return ToSplitEntry(
            date: now, count: 3,
            payments: [sample("Blue Bottle", 1_240, hoursAgo: 2, .wallet), sample("Taqueria", 6_480, hoursAgo: 20, .text),
                       sample("Uber", 2_315, hoursAgo: 30, .screenshot)]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ToSplitEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(from: Date())[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ToSplitEntry>) -> Void) {
        completion(Timeline(entries: entries(from: Date()), policy: .never))
    }

    private func entries(from now: Date) -> [ToSplitEntry] {
        let pending = PaymentInboxFile.shared.read().pending
        let snapshot = ToSplitSnapshot.load(from: PaymentInboxFile.sharedDefaults)
        return ([now] + snapshot.changes(in: pending, after: now)).map { moment in
            let toSplit = snapshot.toSplit(in: pending, at: moment)
            return ToSplitEntry(
                date: moment,
                count: toSplit.count,
                payments: snapshot.hidesDetails ? [] : Array(toSplit.prefix(Self.mostShown)),
                wrapUp: snapshot.hidesDetails ? nil : snapshot.wrapUps(in: pending, at: moment).first,
                hidesDetails: snapshot.hidesDetails
            )
        }
    }
}

// MARK: Widget

struct ToSplitWidget: Widget {
    /// The one mark for To Split, here and on the control: payments caught from Wallet.
    static let symbol = "wallet.pass"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SpltWidgetKind.inbox, provider: ToSplitProvider()) { entry in
            ToSplitWidgetView(entry: entry)
        }
        .configurationDisplayName("To Split")
        .description("The payments waiting to be split. Mark one as not shared without opening Splt.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium, .systemLarge])
    }
}

struct ToSplitWidgetView: View {
    let entry: ToSplitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(SpltWidgetKind.activityURL)
            .containerBackground(for: .widget) {
                if family.isHomeScreen { Ink.paper }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if entry.count == 0 {
                    Image(systemName: "checkmark")
                        .font(.title3)
                } else {
                    VStack(spacing: 0) {
                        Text("\(entry.count)")
                            .font(Typeface.hero(size: 22))
                            .monospacedDigit()
                            .widgetAccentable()
                        Image(systemName: ToSplitWidget.symbol)
                            .font(.caption2)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(countSentence)
        case .accessoryInline:
            Label(countSentence, systemImage: ToSplitWidget.symbol)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("To Split")
                    .font(.headline)
                    .widgetAccentable()
                Text(countSentence)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            small
        default:
            list(rows: family == .systemLarge ? ToSplitProvider.mostShown : 2)
        }
    }

    private var countSentence: String {
        entry.count == 0
            ? String(localized: "Nothing to split")
            : String(localized: "^[\(entry.count) payment](inflect: true) to split")
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: ToSplitWidget.symbol)
                .font(.title3)
                .foregroundStyle(Ink.secondary)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            if entry.count == 0 {
                Text("Nothing to split")
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.text)
            } else {
                Text("\(entry.count)")
                    .font(Typeface.hero(size: 48))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text)
                    .widgetAccentable()
                Text("To Split")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(countSentence)
    }

    // MARK: Medium and large

    private func list(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: ToSplitWidget.symbol)
                    .accessibilityHidden(true)
                Text("To Split")
            }
            .font(.footnote)
            .foregroundStyle(Ink.secondary)
            .padding(.bottom, 4)
            if entry.hidesDetails {
                Spacer(minLength: 0)
                Text(countSentence)
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.text)
                if entry.count > 0 {
                    Text("Open Splt to see them.")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 0)
            } else if entry.count == 0, entry.wrapUp == nil {
                Spacer(minLength: 0)
                Text("Nothing to split")
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.text)
                Text("Payments you catch wait here.")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                Spacer(minLength: 0)
            } else {
                let payments = Array(entry.payments.prefix(rows - (entry.wrapUp == nil ? 0 : 1)))
                if let wrapUp = entry.wrapUp {
                    WrapUpRow(wrapUp: wrapUp)
                    if !payments.isEmpty { Divider().overlay(Ink.hairline) }
                }
                ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                    if index > 0 { Divider().overlay(Ink.hairline) }
                    PaymentRow(payment: payment)
                }
                Spacer(minLength: 0)
                let more = entry.count - payments.count
                if more > 0 {
                    Text("^[\(more) more](inflect: true) in Splt")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One payment, laid out like a To Split row in the app, with the one action that needs no app.
private struct PaymentRow: View {
    let payment: PendingPayment

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Link(destination: SpltWidgetKind.paymentURL(payment.id)) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol)
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(payment.merchant)
                            .font(.subheadline)
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                            .privacySensitive()
                        Text(payment.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .font(.caption)
                            .foregroundStyle(Ink.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(MoneyFormatting.magnitudeString(payment.amount))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                        .privacySensitive()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(payment.merchant), \(MoneyFormatting.magnitudeString(payment.amount))")
                .accessibilityHint("Opens the expense, filled in.")
            }
            Button(intent: NotSharedIntent(paymentID: payment.id)) {
                Text("Not Shared")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Ink.secondary)
            .accessibilityLabel("Not Shared: \(payment.merchant)")
        }
        .padding(.vertical, 6)
    }

    private var symbol: String {
        switch payment.source {
        case .wallet: "wallet.pass"
        case .text: "message"
        case .screenshot: "photo"
        }
    }
}

/// A trip that ended lately, as the app offers it at the top of To Split.
private struct WrapUpRow: View {
    let wrapUp: ToSplitSnapshot.WrapUp

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "suitcase.rolling")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Wrap Up \(wrapUp.tripName)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .privacySensitive()
                Text("^[\(wrapUp.paymentIDs.count) payment](inflect: true) from the trip, split in one go")
                    .font(.caption)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private extension WidgetFamily {
    var isHomeScreen: Bool {
        switch self {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: true
        default: false
        }
    }
}

#Preview("Medium", as: .systemMedium) {
    ToSplitWidget()
} timeline: {
    ToSplitProvider.sample()
    ToSplitEntry(date: Date(), count: 0)
}
