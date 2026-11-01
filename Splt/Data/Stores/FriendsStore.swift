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
    private(set) var didFailToLoad = false

    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false

    init(people: any PersonRepository, container: ModelContainer? = nil) {
        self.people = people
        if let container {
            observer = ContainerChangeObserver(container: container) { [weak self] in self?.scheduleRefresh() }
        }
        refresh()
    }

    /// Friends you are not square with.
    var unsettled: [FriendSummary] { summaries.filter { !$0.isSettled } }

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
            didFailToLoad = false
        } catch {
            didFailToLoad = true
        }
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
