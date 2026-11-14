import Foundation
import SpltCore

/// Turns a payment into an expense you paid, split the way the group usually splits.
@MainActor
struct PaymentSplitter {
    let services: DataServices

    func split(_ payment: PendingPayment, into group: SplitGroup, category: ExpenseCategory?) throws -> Expense {
        let me = try services.people.me() ?? services.people.ensureMe(name: String(localized: "You"))
        var members = group.memberIDs
        if !members.contains(me.id) { members.append(me.id) }
        let expense = Expense(
            groupID: group.id,
            title: payment.merchant,
            total: payment.amount,
            date: payment.date,
            category: category ?? PaymentScorer.kind(of: payment).map { ExpenseCategory($0) } ?? .general,
            payers: [me.id: payment.amount],
            split: Self.definition(for: group, members: members)
        )
        try services.expenses.add(expense)
        return expense
    }

    /// The group's default split for these members, or an equal split when it has none that still works.
    static func definition(for group: SplitGroup, members: [PersonID]) -> SplitDefinition {
        guard let resolved = group.defaultSplit?.resolved(for: members) else {
            return .equal(participants: Set(members))
        }
        switch resolved.method {
        case .equal: return .equal(participants: Set(resolved.participants))
        case .percentages: return .percentages(basisPoints: resolved.weights)
        case .shares: return .shares(weights: resolved.weights)
        }
    }
}
