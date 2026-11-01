import Foundation
import SpltCore

/// One payment that would square you with a friend inside one group and currency.
struct SettleLeg: Identifiable, Hashable, Sendable {
    var groupID: GroupID
    var groupName: String
    var debt: Debt
    /// True when you are the one who owes.
    var youOwe: Bool

    var id: String { "\(groupID)-\(debt.amount.currencyCode)" }

    var route: SettleRoute { SettleRoute(groupID: groupID, debts: [debt]) }

    /// Builds the legs from a friend's per group balance. Positive amounts mean the friend owes you.
    static func make(
        from byGroup: [GroupAmounts], friend: PersonID, me: PersonID, groups: [GroupID: SplitGroup]
    ) -> [SettleLeg] {
        byGroup.flatMap { entry -> [SettleLeg] in
            let name = groups[entry.groupID].map(Self.displayName) ?? String(localized: "Group")
            return entry.amounts.compactMap { amount in
                guard !amount.isZero else { return nil }
                let magnitude = Money(minorUnits: abs(amount.minorUnits), currencyCode: amount.currencyCode)
                let debt = amount.isPositive
                    ? Debt(debtor: friend, creditor: me, amount: magnitude)
                    : Debt(debtor: me, creditor: friend, amount: magnitude)
                return SettleLeg(groupID: entry.groupID, groupName: name, debt: debt, youOwe: amount.isNegative)
            }
        }
    }

    /// The hidden two person group behind a friend is shown as direct expenses.
    static func displayName(of group: SplitGroup) -> String {
        group.kind == .friend ? String(localized: "Direct expenses") : group.name
    }
}

/// A request to settle with a friend. The flow asks which group when there is more than one.
struct SettleRequest: Identifiable, Hashable, Sendable {
    let id = UUID()
    var friendName: String
    var legs: [SettleLeg]
}
