import Foundation
import UIKit

/// Shows a friendly local notification when a change from another person arrives while the app is
/// in the background. It reads the activity entries that sync delivered, so no server is involved.
@MainActor
final class RemoteChangeNotifier {
    private let poster: any LocalNotificationPosting
    private let isEnabled: @MainActor () -> Bool
    private let isInBackground: @MainActor () -> Bool
    private let now: @MainActor () -> Date

    init(
        poster: any LocalNotificationPosting = SystemNotificationPoster(),
        isEnabled: @escaping @MainActor () -> Bool = {
            UserDefaults.standard.bool(forKey: Preferences.Key.notificationsEnabled)
        },
        isInBackground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState != .active },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.poster = poster
        self.isEnabled = isEnabled
        self.isInBackground = isInBackground
        self.now = now
    }

    func notify(for report: ApplyReport, services: DataServices?) {
        guard let services, isEnabled(), isInBackground() else { return }
        let activities = report.inserted.filter { $0.recordType == .activity }
        guard !activities.isEmpty else { return }
        let names = ChangeMessages.Names(
            me: try? services.people.me()?.id,
            person: { (try? services.people.person(id: $0))?.name },
            group: { (try? services.groups.group(id: $0))?.name }
        )
        let contents = ChangeMessages.contents(for: activities, names: names, now: now())
        guard !contents.isEmpty else { return }
        Task {
            guard await poster.isAuthorized() else { return }
            for content in contents {
                await poster.post(content)
            }
        }
    }

    /// Call when the person turns notifications on in Settings.
    func requestAuthorization() async -> Bool {
        await poster.requestAuthorization()
    }
}
