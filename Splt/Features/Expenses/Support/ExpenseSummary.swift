import Foundation
import SpltCore

/// The words and numbers a row or detail screen shows for one expense, worked out in plain code
/// so they can be tested without a view.
struct ExpenseSummary: Equatable {
    var paidBy: String
    /// What the current person owes for the expense. Nil when they are not part of it.
    var myShare: Money?
    /// What the current person paid. Nil when they did not pay.
    var myPayment: Money?

    init(expense: Expense, currentPerson: PersonID?, names: [PersonID: String]) {
        paidBy = Self.payerText(expense.payers, currentPerson: currentPerson, names: names)
        if let currentPerson, expense.split.participants.contains(currentPerson) {
            myShare = (try? expense.shares())?.shares[currentPerson]
        }
        if let currentPerson {
            myPayment = expense.payers[currentPerson]
        }
    }

    static func payerText(_ payers: [PersonID: Money], currentPerson: PersonID?, names: [PersonID: String]) -> String {
        let ordered = payers.keys.sorted()
        func name(_ id: PersonID) -> String {
            if id == currentPerson { return String(localized: "You") }
            return names[id] ?? String(localized: "Someone")
        }
        switch ordered.count {
        case 0:
            return String(localized: "Nobody paid")
        case 1:
            let who = name(ordered[0])
            return ordered[0] == currentPerson ? String(localized: "You paid") : String(localized: "\(who) paid")
        case 2:
            let first = name(ordered[0]), second = name(ordered[1])
            return String(localized: "\(first) and \(second) paid")
        default:
            let count = ordered.count
            return String(localized: "\(count) people paid")
        }
    }
}
