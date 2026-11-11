import Foundation
import SpltCore

/// A reminder that reaches the friend in Splt. It is written as an activity row into each shared
/// group where they owe you, and that row syncs to them like any other. It only works when the
/// friend uses Splt and the group is shared through iCloud, and it can be sent once a day per group.
@MainActor
struct InAppReminder {
    /// One group the reminder goes to, and what the friend owes you there.
    struct Target: Equatable, Sendable {
        var groupID: GroupID
        var amounts: [Money]
    }

    enum State: Equatable, Sendable {
        /// The friend doesn't use Splt, or owes you only in groups that aren't shared.
        case unavailable
        case ready([Target])
        /// You already reminded them today in every group where they owe you.
        case sentToday
        case sent

        var isReady: Bool {
            if case .ready = self { true } else { false }
        }
    }

    let services: DataServices
    var now: @Sendable () -> Date = { Date() }
    var calendar: Calendar = .current

    /// Groups in each of which the friend owes you and would receive a reminder.
    ///
    /// - Parameter synced: the groups shared through iCloud, by you or with you.
    static func targets(friend: Person, balance: FriendBalance, groups: [GroupID: SplitGroup], synced: Set<GroupID>) -> [Target] {
        // someone added by name, who never joined, has no device to reach
        guard !friend.isPlaceholder, !friend.isMe, friend.claimedByCloudUserID != nil else { return [] }
        return balance.byGroup.compactMap { entry in
            let owed = entry.amounts.filter(\.isPositive)
            guard !owed.isEmpty, synced.contains(entry.groupID),
                  let group = groups[entry.groupID], group.memberIDs.contains(friend.id) else { return nil }
            return Target(groupID: entry.groupID, amounts: owed)
        }
        .sorted { $0.groupID < $1.groupID }
    }

    /// True when you haven't reminded the friend in this group today. At most one a day per person per group.
    static func canRemind(
        _ friend: PersonID, in group: GroupID, me: PersonID?, entries: [ActivityEntry], now: Date, calendar: Calendar
    ) -> Bool {
        !entries.contains { entry in
            guard entry.groupID == group, entry.actorID == me,
                  case .reminderSent(let recipient, _) = entry.event, recipient == friend else { return false }
            return calendar.isDate(entry.createdAt, inSameDayAs: now)
        }
    }

    /// What the sheet can offer for this friend right now.
    func state(for friend: Person, synced: Set<GroupID>) -> State {
        guard let balance = try? services.people.friendBalance(with: friend.id) else { return .unavailable }
        let groups = Dictionary(
            ((try? services.groups.groups(includeArchived: true)) ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let all = Self.targets(friend: friend, balance: balance, groups: groups, synced: synced)
        guard !all.isEmpty else { return .unavailable }
        let open = openTargets(all, friend: friend.id)
        return open.isEmpty ? .sentToday : .ready(open)
    }

    /// Writes the reminder into each group that hasn't had one for this friend today.
    /// Returns how many groups it went to.
    @discardableResult
    func send(to friend: PersonID, targets: [Target]) throws -> Int {
        let open = openTargets(targets, friend: friend)
        for target in open {
            try services.activity.recordReminder(to: friend, amounts: target.amounts, in: target.groupID)
        }
        return open.count
    }

    private func openTargets(_ targets: [Target], friend: PersonID) -> [Target] {
        let me = try? services.people.me()?.id
        return targets.filter { target in
            let entries = (try? services.activity.entries(in: target.groupID, limit: 200)) ?? []
            return Self.canRemind(friend, in: target.groupID, me: me, entries: entries, now: now(), calendar: calendar)
        }
    }
}
