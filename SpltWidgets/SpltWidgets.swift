import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct SpltWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ToSplitWidget()
        ToSplitControl()
        TripLiveActivityWidget()
    }
}

// MARK: To Split count

struct ToSplitEntry: TimelineEntry {
    let date: Date
    let count: Int
}

/// Reads the count the app worked out. Before the app has opened, every waiting payment counts.
struct ToSplitProvider: TimelineProvider {
    func placeholder(in context: Context) -> ToSplitEntry {
        ToSplitEntry(date: Date(), count: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (ToSplitEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ToSplitEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> ToSplitEntry {
        let defaults = PaymentInboxFile.sharedDefaults
        let count = defaults.object(forKey: PaymentInboxFile.toSplitCountKey) as? Int
            ?? PaymentInboxFile.shared.read().pending.count
        return ToSplitEntry(date: Date(), count: count)
    }
}

struct ToSplitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SpltWidgetKind.inbox, provider: ToSplitProvider()) { entry in
            ToSplitWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(SpltWidgetKind.activityURL)
        }
        .configurationDisplayName("To Split")
        .description("How many payments are waiting to be split.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct ToSplitWidgetView: View {
    let entry: ToSplitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.count)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "tray")
                        .font(.caption2)
                }
            }
            .accessibilityLabel(label)
        case .accessoryInline:
            Label(label, systemImage: "tray")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Splt")
                    .font(.headline)
                Text(label)
                    .font(.body)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.count)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("To Split")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
    }

    private var label: String {
        entry.count == 0
            ? String(localized: "Nothing to split")
            : String(localized: "^[\(entry.count) payment](inflect: true) to split")
    }
}

// MARK: Control Center

struct ToSplitControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SpltWidgetKind.inboxControl) {
            ControlWidgetButton(action: OpenInboxIntent()) {
                Label("To Split", systemImage: "tray.full")
            }
        }
        .displayName("To Split")
        .description("Opens the payments waiting to be split.")
    }
}

// MARK: Trip Live Activity

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "suitcase.rolling")
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.tripName)
                        .font(.headline)
                    Text(summary(context.state))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .widgetURL(SpltWidgetKind.activityURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.tripName, systemImage: "suitcase.rolling")
                        .font(.subheadline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.totalText)
                        .font(.subheadline)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("^[\(context.state.unsplitCount) payment](inflect: true) to split")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "suitcase.rolling")
            } compactTrailing: {
                Text("\(context.state.unsplitCount)")
                    .monospacedDigit()
            } minimal: {
                Text("\(context.state.unsplitCount)")
                    .monospacedDigit()
            }
            .widgetURL(SpltWidgetKind.activityURL)
        }
    }

    private func summary(_ state: TripActivityAttributes.ContentState) -> String {
        state.unsplitCount == 0
            ? String(localized: "All split")
            : String(localized: "\(state.unsplitCount) unsplit · \(state.totalText)")
    }
}
