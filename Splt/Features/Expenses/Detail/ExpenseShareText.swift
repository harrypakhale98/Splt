import Foundation
import SpltCore

/// The plain text version of an expense, for the share sheet.
enum ExpenseShareText {
    static func make(
        expense: Expense, groupName: String?, names: [PersonID: String], locale: Locale = .current
    ) -> String {
        // A refund keeps its minus sign, as on the expense itself, so it never reads as spending.
        func amount(_ money: Money) -> String {
            MoneyFormatting.string(money, locale: locale, showsSign: expense.isRefund && money.isNegative)
        }
        let date = expense.date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
        var lines = [expense.title]
        var headline = "\(amount(expense.total)), \(date)"
        if let groupName { headline += ", \(groupName)" }
        if expense.isRefund { headline = String(localized: "Refund") + ", " + headline }
        lines.append(headline)

        let payers = expense.payers.keys.sorted()
        if payers.count == 1, let only = payers.first {
            lines.append(String(localized: "Paid by \(names[only] ?? String(localized: "someone"))"))
        } else {
            lines.append(String(localized: "Paid by"))
            for payer in payers {
                lines.append("  \(names[payer] ?? String(localized: "Someone")): \(amount(expense.payers[payer]!))")
            }
        }

        if let result = try? expense.shares() {
            lines.append(String(localized: "Split"))
            for (person, share) in result.shares.sorted(by: { (names[$0.key] ?? "") < (names[$1.key] ?? "") }) {
                lines.append("  \(names[person] ?? String(localized: "Someone")): \(amount(share))")
            }
        }
        if !expense.note.isEmpty { lines.append(expense.note) }
        return lines.joined(separator: "\n")
    }
}
