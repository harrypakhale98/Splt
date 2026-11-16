import Foundation
import SpltCore
import UIKit

/// Keeps scheduled reminders true to the balances, wherever the change came from. A reminder goes once
/// its friend owes you nothing, is blocked or is gone, and the rest are posted again with what is owed now
/// and with the Face ID lock's privacy, so a lock turned on later hides the amounts on the lock screen too.
///
/// The friends store hands it every refresh; it also checks when the app goes to the background and
/// when the lock is turned on or off.
@MainActor
final class ReminderSweeper {
    private let center: any ReminderCenter
    private let notificationsEnabled: @MainActor () -> Bool
    private let isHidingDetails: @MainActor () -> Bool
    private let visibility: FriendVisibilityStore

    /// What each friend owes you now, positive amounts only.
    private var owed: [PersonID: (name: String, amounts: [Money])] = [:]
    /// Nothing is known about balances until the first friends read, and an empty list must not be taken
    /// for "nobody owes you": a read that failed at launch would otherwise wipe every reminder.
    private var hasRead = false
    /// What the pending reminders were last written from, so an unrelated save does not rewrite them.
    private var written: (owed: [PersonID: [Money]], hiding: Bool)?
    private var running: Task<Void, Never>?
    private var sweepsAgain = false
    nonisolated(unsafe) private var tokens: [any NSObjectProtocol] = []

    init(
        center: any ReminderCenter = SystemReminderCenter(),
        notificationsEnabled: @escaping @MainActor () -> Bool = {
            UserDefaults.standard.bool(forKey: Preferences.Key.notificationsEnabled)
        },
        isHidingDetails: @escaping @MainActor () -> Bool = { NotificationPrivacy.isHidingDetails() },
        visibility: FriendVisibilityStore = FriendVisibilityStore(),
        observesApp: Bool = true
    ) {
        self.center = center
        self.notificationsEnabled = notificationsEnabled
        self.isHidingDetails = isHidingDetails
        self.visibility = visibility
        guard observesApp else { return }
        tokens.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep(force: true) }
        })
        // the lock is a stored preference, and it can also be turned off for you when the passcode goes
        tokens.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockMayHaveChanged() }
        })
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }

    /// Takes the friends as they are now and sweeps when what they owe has changed.
    func update(_ summaries: [FriendSummary]) {
        var owed: [PersonID: (name: String, amounts: [Money])] = [:]
        for summary in summaries {
            let amounts = summary.balance.filter(\.isPositive)
            if !amounts.isEmpty { owed[summary.id] = (summary.person.name, amounts) }
        }
        self.owed = owed
        hasRead = true
        sweep(force: false)
    }

    /// Waits for the sweep in flight, for tests.
    func settle() async {
        while let running { await running.value }
    }

    private func lockMayHaveChanged() {
        guard let written, written.hiding != isHidingDetails() else { return }
        sweep(force: true)
    }

    private func sweep(force: Bool) {
        guard hasRead else { return }
        guard force || written.map({ $0.owed != owedAmounts || $0.hiding != isHidingDetails() }) ?? true else { return }
        guard running == nil else {
            sweepsAgain = true
            return
        }
        running = Task { [weak self] in
            await self?.run()
        }
    }

    private var owedAmounts: [PersonID: [Money]] { owed.mapValues(\.amounts) }

    private func run() async {
        repeat {
            sweepsAgain = false
            await rewritePending()
        } while sweepsAgain
        running = nil
    }

    private func rewritePending() async {
        let hiding = isHidingDetails()
        let basis = (owed: owedAmounts, hiding: hiding)
        // with Notifications off there is nothing pending: turning it off removed every reminder
        guard notificationsEnabled() else {
            written = basis
            return
        }
        for request in await center.pending(withPrefix: ReminderScheduler.identifierPrefix) {
            guard let friend = ReminderScheduler.friend(in: request.identifier),
                  let now = owed[friend], visibility.state(of: friend) != .blocked else {
                await center.remove(identifier: request.identifier)
                continue
            }
            var updated = request
            updated.title = ReminderMessage.notificationTitle(friendName: now.name)
            updated.body = ReminderMessage.notificationBody(friendName: now.name, amounts: now.amounts)
            // the same identifier replaces the pending one, keeping its time and link
            try? await center.add(updated)
        }
        written = basis
    }
}
