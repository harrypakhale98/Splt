import Foundation
import SwiftUI

/// Reminders you sent are taken away after a week, for everyone in the group. By then they have
/// done their job, and it is what clears them from devices still on version 1.0, which count a
/// reminder as unread without being able to show it.
@MainActor
enum ReminderExpiry {
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    @discardableResult
    static func run(services: DataServices, now: Date = Date()) -> Int {
        (try? services.activity.expireReminders(sentBefore: now.addingTimeInterval(-lifetime))) ?? 0
    }
}

private struct ExpiresReminders: ViewModifier {
    @Environment(\.dataServices) private var services
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.task(id: phase) {
            guard phase == .active, let services else { return }
            ReminderExpiry.run(services: services)
        }
    }
}

extension View {
    /// Removes week-old reminders you sent whenever the app becomes active.
    func expiresReminders() -> some View {
        modifier(ExpiresReminders())
    }
}
