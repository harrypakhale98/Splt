import Foundation
import SpltCore

/// Writes a group in the layout Splitwise uses: Date, Description, Category, Cost, Currency, then one
/// column per member holding what that person paid minus what they owe for the row.
/// Settlements are rows with the category "Payment". A "Total balance" row closes each currency.
enum GroupCSVExporter {
    static let totalBalanceLabel = "Total balance"
    static let paymentCategory = "Payment"
    static let posix = Locale(identifier: "en_US_POSIX")

    static func data(for snapshot: GroupExportSnapshot, timeZone: TimeZone = .current) -> Data {
        Data(text(for: snapshot, timeZone: timeZone).utf8)
    }

    static func text(for snapshot: GroupExportSnapshot, timeZone: TimeZone = .current) -> String {
        let people = snapshot.people
        let names = uniqueNames(people)
        var lines = [CSVText.line(["Date", "Description", "Category", "Cost", "Currency"] + names.map(CSVText.neutralized))]
        let dateText = dateFormatter(timeZone)

        var entries: [(date: Date, line: String)] = []
        for expense in snapshot.expenses {
            guard let net = try? expense.netBalances() else { continue }
            let cells = people.map { amountText(net[$0.id]) }
            entries.append((expense.date, CSVText.line([
                dateText.string(from: expense.date), CSVText.neutralized(expense.title),
                expense.category.rawValue, amountText(expense.total), expense.total.currencyCode
            ] + cells)))
        }
        for payment in snapshot.payments {
            let payer = people.first { $0.id == payment.payer }?.name ?? "?"
            let receiver = people.first { $0.id == payment.receiver }?.name ?? "?"
            let cells = people.map { person -> String in
                if person.id == payment.payer { return amountText(payment.amount) }
                if person.id == payment.receiver { return amountText(negated(payment.amount)) }
                return amountText(nil)
            }
            entries.append((payment.date, CSVText.line([
                dateText.string(from: payment.date), CSVText.neutralized("\(payer) paid \(receiver)"),
                paymentCategory, amountText(payment.amount), payment.amount.currencyCode
            ] + cells)))
        }
        lines += entries.sorted { $0.date < $1.date }.map(\.line)

        let ledger = Ledger(expenses: snapshot.expenses, payments: snapshot.payments)
        for currency in ledger.currencies {
            let table = ledger.netBalances[currency] ?? [:]
            let cells = people.map { amountText(table[$0.id]) }
            lines.append(CSVText.line(["", totalBalanceLabel, "", "", currency] + cells))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func amountText(_ money: Money?) -> String {
        money?.plainString(locale: posix) ?? ""
    }

    private static func negated(_ money: Money) -> Money {
        Money(minorUnits: -money.minorUnits, currencyCode: money.currencyCode)
    }

    private static func dateFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Two people with the same name would share a column, so later ones get a number.
    private static func uniqueNames(_ people: [Person]) -> [String] {
        var seen: [String: Int] = [:]
        return people.map { person in
            let count = seen[person.name, default: 0] + 1
            seen[person.name] = count
            return count == 1 ? person.name : "\(person.name) (\(count))"
        }
    }
}
