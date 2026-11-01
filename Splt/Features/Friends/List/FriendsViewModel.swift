import Foundation
import Observation
import SpltCore

/// The Friends tab: friends sorted by who owes whom, with search and the local hide and block list.
@MainActor
@Observable
final class FriendsViewModel {
    var query = ""
    var errorMessage: String?

    /// Bumped when the hide and block list changes, because that list lives in user defaults.
    private var visibilityRevision = 0

    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let visibility: FriendVisibilityStore

    init(services: DataServices, visibility: FriendVisibilityStore = FriendVisibilityStore()) {
        self.services = services
        self.visibility = visibility
    }

    var sections: FriendSections {
        _ = visibilityRevision
        return FriendSections(summaries: summaries, leftOut: visibility.hiddenOrBlocked, query: query)
    }

    var summaries: [FriendSummary] { services.friendsStore.summaries }
    var totals: BalanceTotals { services.friendsStore.totals }

    /// True before the first friend exists, so the tab can invite people to add one.
    var hasNoFriends: Bool { summaries.isEmpty }

    var hiddenSummaries: [FriendSummary] {
        _ = visibilityRevision
        let left = visibility.hiddenOrBlocked
        return summaries.filter { left.contains($0.id) }
    }

    func state(of id: PersonID) -> FriendVisibilityStore.State? {
        _ = visibilityRevision
        return visibility.state(of: id)
    }

    func setState(_ state: FriendVisibilityStore.State?, for id: PersonID) {
        visibility.set(state, for: id)
        visibilityRevision += 1
    }

    /// The payments that would square you with this friend, one per group and currency.
    func settleRequest(for summary: FriendSummary) -> SettleRequest? {
        guard let me = try? services.people.me() else { return nil }
        let groups = Dictionary(
            ((try? services.groups.groups(includeArchived: true)) ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let legs = SettleLeg.make(from: summary.byGroup, friend: summary.id, me: me.id, groups: groups)
        guard !legs.isEmpty else { return nil }
        return SettleRequest(friendName: summary.person.name, legs: legs)
    }

    func refresh() {
        services.friendsStore.refresh()
    }
}
