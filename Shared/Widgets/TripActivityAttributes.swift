import ActivityKit
import Foundation

/// The Lock Screen line for a trip in progress: how many payments still wait and what they add up to.
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var unsplitCount: Int
        /// Already formatted by the app, one amount per currency, so the widget needs no money rules.
        var totalText: String
    }

    var groupID: UUID
    var tripName: String
}

/// Shared names between the app and its widgets.
enum SpltWidgetKind {
    static let inbox = "com.harrypakhale.splt.inbox"
    static let inboxControl = "com.harrypakhale.splt.inbox-control"
    static let activityURL = URL(string: "splt://activity")!
}
