import Foundation
import Observation
import SpltCore
import SwiftData

/// Friends with what each owes you, for the Friends tab.
@MainActor
@Observable
final class FriendsStore {
    private(set) var summaries: [FriendSummary] = []
    private(set) var totals = BalanceTotals.zero

    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false
    /// Scheduled reminders follow every refresh, so they keep up even while the Friends tab is closed.
    @ObservationIgnored private let reminders: ReminderSweeper?

    init(people: any PersonRepository, container: ModelContainer? = nil, reminders: ReminderSweeper? = nil) {
        self.people = people
        self.reminders = reminders ?? (container == nil ? nil : ReminderSweeper())
        if let container {
            observer = ContainerChangeObserver(container: container) { [weak self] in self?.scheduleRefresh() }
        }
        refresh()
    }

    /// Reads the friends again. A failed read keeps what was there.
    func refresh() {
        do {
            let balances = Dictionary(
                try people.friendBalances().map { ($0.friendID, $0) }, uniquingKeysWith: { first, _ in first }
            )
            summaries = try people.friends().map { friend in
                let balance = balances[friend.id]
                return FriendSummary(person: friend, balance: balance?.total ?? [], byGroup: balance?.byGroup ?? [])
            }
            totals = BalanceTotals(amounts: summaries.flatMap(\.balance))
            reminders?.update(summaries)
        } catch {}
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }
}
