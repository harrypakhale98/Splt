import ActivityKit
import SwiftUI
import WidgetKit

/// The trip happening now on the Lock Screen and in the Dynamic Island: how much is still to split.
struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "suitcase.rolling")
                    .font(.title3)
                    .foregroundStyle(Ink.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.tripName)
                        .font(Typeface.heading)
                        .foregroundStyle(Ink.text)
                    Text(context.isStale ? String(localized: "Trip over · tap to wrap up") : summary(context.state))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Ink.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Ink.paper)
            .activitySystemActionForegroundColor(Ink.text)
            .widgetURL(SpltWidgetKind.activityURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.tripName, systemImage: "suitcase.rolling")
                        .font(.subheadline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.totalText)
                        .font(Typeface.figure)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(countSentence(context.state))
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

    private func countSentence(_ state: TripActivityAttributes.ContentState) -> String {
        state.unsplitCount == 0
            ? String(localized: "Nothing to split")
            : String(localized: "^[\(state.unsplitCount) payment](inflect: true) to split")
    }

    private func summary(_ state: TripActivityAttributes.ContentState) -> String {
        state.unsplitCount == 0
            ? countSentence(state)
            : String(localized: "\(countSentence(state)) · \(state.totalText)")
    }
}
