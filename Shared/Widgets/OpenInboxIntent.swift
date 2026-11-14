import AppIntents
import Foundation

/// Opens Splt on the To Split list. Built into the app and the widgets, so the Control Center
/// button can run it and the app opens where it should.
struct OpenInboxIntent: AppIntent {
    static let title: LocalizedStringResource = "Open To Split"
    static let description = IntentDescription("Opens the payments waiting to be split.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SpltWidgetKind.activityURL))
    }
}
