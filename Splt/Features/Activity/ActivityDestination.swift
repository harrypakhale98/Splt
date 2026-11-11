import Foundation
import SpltCore

/// Where tapping a feed row goes: the expense, the friend or the group it is about.
enum ActivityDestination {
    static func route(
        for entry: ActivityEntry, me: PersonID?, groups: [GroupID: SplitGroup]
    ) -> Route? {
        let group = entry.groupID.flatMap { groups[$0] }
        switch entry.event {
        case .expenseAdded(let expense), .expenseEdited(let expense), .expenseRestored(let expense):
            return .expense(expense.id.rawValue)
        case .commentAdded(let expense, _):
            if let expense { return .expense(expense.id.rawValue) }
            return groupRoute(entry, group, me: me)
        case .paymentRecorded(let payment), .paymentUndone(let payment):
            let other = payment.payer == me ? payment.receiver : (payment.receiver == me ? payment.payer : nil)
            if let other { return .friend(other.rawValue) }
            return groupRoute(entry, group, me: me)
        case .memberAdded(let person), .memberRemoved(let person):
            if person != me, group?.kind != .friend { return .friend(person.rawValue) }
            return groupRoute(entry, group, me: me)
        case .reminderSent(let recipient, _):
            let other = entry.actorID == me ? recipient : entry.actorID
            if let other, other != me, group?.kind != .friend { return .friend(other.rawValue) }
            return groupRoute(entry, group, me: me)
        case .expenseDeleted, .groupCreated, .groupRenamed, .groupArchived, .groupRestored, .expensesImported:
            return groupRoute(entry, group, me: me)
        }
    }

    private static func groupRoute(_ entry: ActivityEntry, _ group: SplitGroup?, me: PersonID?) -> Route? {
        guard let id = entry.groupID else { return nil }
        if let group, group.kind == .friend, let other = group.memberIDs.first(where: { $0 != me }) {
            return .friend(other.rawValue)
        }
        return .group(id.rawValue)
    }
}
