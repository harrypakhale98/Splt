import Foundation
import SpltCore
import UIKit
import WidgetKit

/// Keeps the Your Balance widget in step with the store. It saves a `BalanceWidgetSnapshot` after anything
/// saves to the store, sync included, when the app comes forward, when a friend is hidden or shown, and
/// when the Face ID lock changes. It reloads the widget only when what it shows has changed.
@MainActor
final class BalanceWidgetPublisher {
    private static var running: BalanceWidgetPublisher?

    /// Starts with the app's data wherever the app opens it: the window, an intent or a sync wake-up.
    /// Starting again on the same data does nothing; on other data, such as a debug build's sample trip, it moves to that.
    static func start(services: DataServices) {
        guard running?.services !== services else { return }
        running = BalanceWidgetPublisher(services: services, defaults: PaymentInboxFile.sharedDefaults)
    }

    /// Saves now, for a change the store doesn't see, such as the Face ID lock.
    static func refresh() {
        running?.publish()
    }

    private let services: DataServices
    private let defaults: UserDefaults
    private let visibility: FriendVisibilityStore
    private var observer: ContainerChangeObserver?
    nonisolated(unsafe) private var tokens: [any NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    init(services: DataServices, defaults: UserDefaults, visibility: FriendVisibilityStore = FriendVisibilityStore()) {
        self.services = services
        self.defaults = defaults
        self.visibility = visibility
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.schedule() }
        for name in [UIApplication.didBecomeActiveNotification, FriendVisibilityStore.didChange] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        publish()
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }

    /// Waits a moment, so the friends store has read the change and a burst of saves publishes once.
    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    private func publish() {
        let store = services.friendsStore
        store.refresh()
        let snapshot = Self.snapshot(
            summaries: store.summaries, totals: store.totals, hidden: visibility.hiddenOrBlocked,
            hidesDetails: NotificationPrivacy.isHidingDetails()
        )
        guard snapshot != BalanceWidgetSnapshot.load(from: defaults) else { return }
        snapshot.save(to: defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: SpltWidgetKind.balance)
    }

    /// The same totals as the Friends tab hero, and the friends with the most money between you,
    /// leaving out anyone hidden or blocked. With the lock on, nothing at all.
    static func snapshot(
        summaries: [FriendSummary], totals: BalanceTotals, hidden: Set<PersonID>, hidesDetails: Bool
    ) -> BalanceWidgetSnapshot {
        guard !hidesDetails else { return .hidden }
        let friends = summaries
            .filter { !$0.balance.isEmpty && !hidden.contains($0.id) }
            .sorted { largest($0.balance) > largest($1.balance) }
            .prefix(BalanceWidgetSnapshot.mostFriends)
            .map { summary in
                let hue = PersonPalette.index(for: summary.id)
                let light = PersonPalette.hexPair(at: hue, dark: false), dark = PersonPalette.hexPair(at: hue, dark: true)
                return BalanceWidgetSnapshot.Friend(
                    id: summary.id.rawValue, name: summary.person.name, balance: summary.balance,
                    initials: AvatarStyle.initials(for: summary.person.name),
                    color: .init(lightFill: light.fill, lightText: light.text, darkFill: dark.fill, darkText: dark.text)
                )
            }
        return BalanceWidgetSnapshot(owedToYou: totals.owedToYou, youOwe: totals.youOwe, friends: friends)
    }

    private static func largest(_ balance: [Money]) -> UInt64 {
        balance.map(\.minorUnits.magnitude).max() ?? 0
    }
}
