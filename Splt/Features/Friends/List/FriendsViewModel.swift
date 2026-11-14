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
    @ObservationIgnored private let reminders: ReminderScheduler
    /// The cancellation a block started last, so tests can wait for it.
    @ObservationIgnored private(set) var reminderCancellation: Task<Void, Never>?

    init(
        services: DataServices, visibility: FriendVisibilityStore = FriendVisibilityStore(),
        reminders: ReminderScheduler = ReminderScheduler()
    ) {
        self.services = services
        self.visibility = visibility
        self.reminders = reminders
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

    /// The friends the Add Expense menu offers, by name. Hidden and blocked friends are left out.
    var expenseFriends: [Person] {
        _ = visibilityRevision
        let left = visibility.hiddenOrBlocked
        return summaries.map(\.person)
            .filter { !left.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The group a new expense with this friend goes into, made the first time it is needed.
    func expenseGroup(with friend: PersonID) -> GroupID? {
        do {
            return try DirectGroupResolver.group(with: friend, services: services)
        } catch {
            errorMessage = SettleErrorMessage.text(for: error)
            return nil
        }
    }

    func state(of id: PersonID) -> FriendVisibilityStore.State? {
        _ = visibilityRevision
        return visibility.state(of: id)
    }

    func setState(_ state: FriendVisibilityStore.State?, for id: PersonID) {
        visibility.set(state, for: id)
        visibilityRevision += 1
        // a blocked friend gets no reminders, so one that is already scheduled must not arrive either
        if state == .blocked {
            reminderCancellation = Task { [reminders] in await reminders.cancel(for: id) }
        }
    }

    /// Picks up a hide or block made elsewhere, such as on a friend's screen.
    func visibilityDidChange() {
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

    /// Drops the scheduled reminder of anyone who no longer owes you, for example after they paid.
    func cancelRemindersForFriendsWhoOweNothing(using scheduler: ReminderScheduler = ReminderScheduler()) async {
        for summary in summaries where !summary.balance.contains(where: \.isPositive) {
            await scheduler.cancel(for: summary.id)
        }
    }
}
