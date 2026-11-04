import Foundation
import SpltCore

/// Reads a CSV exported from Splitwise and rebuilds the expenses and settlements in it.
///
/// Each row holds the cost and, per member, what that person paid minus what they owe. The
/// importer works back from that. With one payer, shares are exact, or an equal split when
/// they are equal. With several payers it assumes an equal split among everyone with a
/// non zero balance. Rows it cannot rebuild are skipped and reported as warnings.
enum SplitwiseCSVImporter {
    private static let fixedColumns = ["date", "description", "category", "cost", "currency"]
    /// More than any real expense, and small enough that sums of a file cannot overflow.
    private static let largestAmount: Int64 = 1_000_000_000_000_000

    static func parse(
        _ text: String,
        groupID: GroupID,
        knownPeople: [String: PersonID] = [:],
        timeZone: TimeZone = .current
    ) throws -> SplitwiseImport {
        let rows = CSVText.rows(text)
        guard let header = rows.first else { throw DataError.unreadableCSV("The file is empty.") }
        let columns = try columnMap(header)

        var known: [String: PersonID] = [:]
        for (name, id) in knownPeople { known[normalized(name)] = id }
        var members: [String: PersonID] = [:]
        var memberOrder: [(name: String, column: Int)] = []
        for column in columns.firstMember..<header.count {
            let name = CSVText.restored(header[column].trimmingCharacters(in: .whitespacesAndNewlines))
            guard !name.isEmpty else { continue }
            memberOrder.append((name, column))
            members[name] = known[normalized(name)] ?? PersonID()
        }

        var result = SplitwiseImport(
            memberNames: memberOrder.map(\.name), members: members, expenses: [], payments: [], warnings: []
        )
        let calendar = calendar(timeZone)

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            func cell(_ column: Int) -> String {
                column < row.count ? row[column].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
            let description = CSVText.restored(cell(columns.description))
            if description.isEmpty && cell(columns.cost).isEmpty { continue }
            if description.caseInsensitiveCompare(GroupCSVExporter.totalBalanceLabel) == .orderedSame { continue }

            func skip(_ message: String) {
                result.warnings.append(ImportWarning(line: line, message: message))
            }
            guard let date = date(cell(columns.date), calendar: calendar) else { skip("Unreadable date."); continue }
            let currency = cell(columns.currency).uppercased()
            guard currency.count == 3 else { skip("Missing currency."); continue }
            guard let cost = try? MoneyParser.parse(cell(columns.cost), currencyCode: currency, locale: GroupCSVExporter.posix),
                  !cost.isZero, abs(cost.minorUnits) <= largestAmount else { skip("Unreadable or zero cost."); continue }

            var nets: [PersonID: Int64] = [:]
            var readable = true
            for member in memberOrder {
                let text = cell(member.column)
                if text.isEmpty { continue }
                guard let amount = try? MoneyParser.parse(text, currencyCode: currency, locale: GroupCSVExporter.posix),
                      abs(amount.minorUnits) <= largestAmount,
                      let id = members[member.name] else { readable = false; break }
                if !amount.isZero { nets[id] = amount.minorUnits }
            }
            guard readable else { skip("Unreadable member amount."); continue }
            guard nets.values.reduce(Int128(0), { $0 + Int128($1) }) == 0 else { skip("Member amounts do not add up to zero."); continue }

            let category = cell(columns.category)
            if category.caseInsensitiveCompare(GroupCSVExporter.paymentCategory) == .orderedSame {
                guard let payment = payment(nets: nets, cost: cost, date: date, groupID: groupID) else {
                    skip("A payment needs exactly one payer and one receiver.")
                    continue
                }
                result.payments.append(payment)
                continue
            }
            guard let expense = expense(
                title: description, category: SplitwiseCategoryMap.category(for: category),
                cost: cost, date: date, nets: nets, groupID: groupID
            ) else { skip("The amounts cannot be matched to payers and shares."); continue }
            result.expenses.append(expense)
        }
        return result
    }

    private static func payment(nets: [PersonID: Int64], cost: Money, date: Date, groupID: GroupID) -> Payment? {
        guard nets.count == 2,
              let payer = nets.first(where: { $0.value > 0 })?.key,
              let receiver = nets.first(where: { $0.value < 0 })?.key else { return nil }
        let amount = Money(minorUnits: abs(cost.minorUnits), currencyCode: cost.currencyCode)
        return Payment(groupID: groupID, payer: payer, receiver: receiver, amount: amount, date: date)
    }

    private static func expense(
        title: String, category: ExpenseCategory, cost: Money, date: Date, nets: [PersonID: Int64], groupID: GroupID
    ) -> Expense? {
        let sign: Int64 = cost.minorUnits < 0 ? -1 : 1
        let total = abs(cost.minorUnits)
        let signed = nets.mapValues { $0 * sign }
        let payers = signed.filter { $0.value > 0 }
        let currency = cost.currencyCode
        func money(_ units: Int64) -> Money { Money(minorUnits: units * sign, currencyCode: currency) }

        let paid: [PersonID: Int64]
        let shares: [PersonID: Int64]
        if payers.count == 1, let payer = payers.first {
            paid = [payer.key: total]
            var owed = signed.filter { $0.value < 0 }.mapValues { -$0 }
            let own = total - payer.value
            guard own >= 0 else { return nil }
            if own > 0 { owed[payer.key] = own }
            shares = owed
        } else if payers.count > 1 {
            let people = Array(signed.keys)
            let equal = try? SplitCalculator.shares(for: .equal(participants: Set(people)), total: Money(minorUnits: total, currencyCode: currency))
            guard let equal else { return nil }
            var contributions: [PersonID: Int64] = [:]
            for person in people {
                let value = signed[person, default: 0] + (equal[person]?.minorUnits ?? 0)
                guard value >= 0 else { return nil }
                if value > 0 { contributions[person] = value }
            }
            paid = contributions
            shares = equal.mapValues(\.minorUnits)
        } else {
            return nil
        }

        let participants = Set(shares.keys)
        let exact = shares.mapValues(money)
        let equalShares = try? SplitCalculator.shares(for: .equal(participants: participants), total: cost)
        let split: SplitDefinition = equalShares == exact ? .equal(participants: participants) : .exact(amounts: exact)
        let expense = Expense(
            groupID: groupID, title: title, total: cost, date: date, category: category,
            payers: paid.mapValues(money), split: split
        )
        return (try? expense.validate()) == nil ? nil : expense
    }

    private struct Columns {
        var date = 0, description = 0, category = 0, cost = 0, currency = 0
        var firstMember: Int { max(date, description, category, cost, currency) + 1 }
    }

    private static func columnMap(_ header: [String]) throws -> Columns {
        let names = header.map { normalized($0) }
        var columns = Columns()
        for name in fixedColumns {
            guard let index = names.firstIndex(of: name) else {
                throw DataError.unreadableCSV("The header has no \(name) column.")
            }
            switch name {
            case "date": columns.date = index
            case "description": columns.description = index
            case "category": columns.category = index
            case "cost": columns.cost = index
            default: columns.currency = index
            }
        }
        return columns
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// A date such as 2025-03-14, placed at noon so a shifted time zone does not change the day.
    private static func date(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2],
              (1900...2200).contains(year) else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day)
        else { return nil }
        return date
    }
}
