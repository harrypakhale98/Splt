import ActivityKit
import Foundation
import SpltCore

/// Keeps one Live Activity for the trip happening now: "Lisbon · 4 unsplit · €312". It starts when the
/// app is open, since iOS only allows that from the foreground, and is updated whenever the inbox changes.
/// It is left off with the Face ID lock on, because it would show amounts on the Lock Screen.
@MainActor
enum TripLiveActivity {
    static func sync(_ review: InboxReview) {
        let running = Activity<TripActivityAttributes>.activities
        guard let trip = review.activeTrip, !NotificationPrivacy.isHidingDetails() else {
            end(running)
            return
        }
        end(running.filter { $0.attributes.groupID != trip.id.rawValue })
        let rows = review.rows.filter(\.isInActiveTrip)
        let state = TripActivityAttributes.ContentState(unsplitCount: rows.count, totalText: totalText(rows.map(\.payment.amount)))
        let content = ActivityContent(state: state, staleDate: nil)
        let tripID = trip.id.rawValue
        if running.contains(where: { $0.attributes.groupID == tripID }) {
            Task {
                // looked up again here, so the activity never crosses into the task
                for activity in Activity<TripActivityAttributes>.activities where activity.attributes.groupID == tripID {
                    await activity.update(content)
                }
            }
        } else if !rows.isEmpty, ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = TripActivityAttributes(groupID: trip.id.rawValue, tripName: trip.name)
            _ = try? Activity.request(attributes: attributes, content: content)
        }
    }

    /// One amount per currency, joined: "€312 + £40".
    static func totalText(_ amounts: [Money]) -> String {
        var sums: [String: Int64] = [:]
        for amount in amounts { sums[amount.currencyCode, default: 0] += amount.minorUnits }
        return sums.sorted { $0.key < $1.key }
            .map { MoneyFormatting.magnitudeString(Money(minorUnits: $0.value, currencyCode: $0.key)) }
            .joined(separator: " + ")
    }

    private static func end(_ activities: [Activity<TripActivityAttributes>]) {
        let ids = Set(activities.map(\.id))
        guard !ids.isEmpty else { return }
        Task {
            for activity in Activity<TripActivityAttributes>.activities where ids.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
