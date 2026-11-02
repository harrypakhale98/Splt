import Foundation
import SpltCore

/// One line of a printed report.
struct ReportRow: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case title
        case heading
        case body
        case caption
        case spacer
    }

    var style: Style
    var leading: String
    var trailing: String?

    init(_ style: Style, _ leading: String = "", trailing: String? = nil) {
        self.style = style
        self.leading = leading
        self.trailing = trailing
    }
}

/// What a group looks like on paper: who owes whom, then every expense and payment.
struct GroupReport: Equatable, Sendable {
    struct ExpenseLine: Equatable, Sendable {
        var date: Date
        var title: String
        var paidBy: String
        var amount: Money
    }

    struct PaymentLine: Equatable, Sendable {
        var date: Date
        var from: String
        var to: String
        var amount: Money
    }

    struct TransferLine: Equatable, Sendable {
        var from: String
        var to: String
        var amount: Money
    }

    struct MemberBalance: Equatable, Sendable {
        var name: String
        /// Positive means the person is owed.
        var amounts: [Money]
    }

    var groupName: String
    var currencyCode: String
    var exportedAt: Date
    var members: [MemberBalance]
    var transfers: [TransferLine]
    var expenses: [ExpenseLine]
    var payments: [PaymentLine]
    var totals: [Money]

    init(
        group: SplitGroup,
        people: [PersonID: Person],
        expenses: [Expense],
        payments: [Payment],
        balances: GroupBalances,
        exportedAt: Date
    ) {
        func name(_ id: PersonID) -> String { people[id]?.name ?? String(localized: "Someone") }
        groupName = group.name
        currencyCode = group.currencyCode
        self.exportedAt = exportedAt
        members = group.memberIDs.map { id in
            MemberBalance(name: name(id), amounts: BalanceLine.lines(for: balances.net(for: id)).map(\.money))
        }
        transfers = balances.suggestedSettlements.map {
            TransferLine(from: name($0.debtor), to: name($0.creditor), amount: $0.amount)
        }
        let live = expenses.filter { !$0.isDeleted }
        self.expenses = live.sorted { $0.date < $1.date }.map { expense in
            let payers = expense.payers.keys.sorted().map(name).joined(separator: ", ")
            return ExpenseLine(date: expense.date, title: expense.title, paidBy: payers, amount: expense.total)
        }
        self.payments = payments.filter { !$0.isDeleted }.sorted { $0.date < $1.date }.map {
            PaymentLine(date: $0.date, from: name($0.payer), to: name($0.receiver), amount: $0.amount)
        }
        totals = GroupTotals.make(expenses: live, names: [:]).map(\.total)
    }

    /// The report as rows, shared by the PDF and the plain text so they always agree.
    func rows(locale: Locale = .current) -> [ReportRow] {
        func money(_ value: Money) -> String { MoneyFormatting.magnitudeString(value, locale: locale) }
        func day(_ date: Date) -> String { date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)) }

        var rows: [ReportRow] = [
            ReportRow(.title, groupName),
            ReportRow(.caption, String(localized: "Exported \(day(exportedAt)). Currency: \(currencyCode)")),
            ReportRow(.spacer)
        ]
        if !totals.isEmpty {
            for total in totals {
                rows.append(ReportRow(.body, String(localized: "Total spent"), trailing: money(total)))
            }
            rows.append(ReportRow(.spacer))
        }

        rows.append(ReportRow(.heading, String(localized: "Balances")))
        for member in members {
            if member.amounts.isEmpty {
                rows.append(ReportRow(.body, member.name, trailing: String(localized: "Settled up")))
            } else {
                for amount in member.amounts {
                    let value = money(amount)
                    let text = amount.minorUnits > 0
                        ? String(localized: "is owed \(value)")
                        : String(localized: "owes \(value)")
                    rows.append(ReportRow(.body, member.name, trailing: text))
                }
            }
        }
        rows.append(ReportRow(.spacer))

        rows.append(ReportRow(.heading, String(localized: "To Settle Up")))
        if transfers.isEmpty {
            rows.append(ReportRow(.body, String(localized: "Everyone is settled up")))
        }
        for transfer in transfers {
            rows.append(ReportRow(.body, String(localized: "\(transfer.from) pays \(transfer.to)"), trailing: money(transfer.amount)))
        }
        rows.append(ReportRow(.spacer))

        rows.append(ReportRow(.heading, String(localized: "Expenses")))
        if expenses.isEmpty {
            rows.append(ReportRow(.body, String(localized: "No expenses")))
        }
        for expense in expenses {
            rows.append(ReportRow(.body, expense.title, trailing: money(expense.amount)))
            rows.append(ReportRow(.caption, "\(day(expense.date)), \(String(localized: "paid by \(expense.paidBy)"))"))
        }

        if !payments.isEmpty {
            rows.append(ReportRow(.spacer))
            rows.append(ReportRow(.heading, String(localized: "Payments")))
            for payment in payments {
                rows.append(ReportRow(.body, String(localized: "\(payment.from) paid \(payment.to)"), trailing: money(payment.amount)))
                rows.append(ReportRow(.caption, day(payment.date)))
            }
        }
        return rows
    }

    func plainText(locale: Locale = .current) -> String {
        rows(locale: locale).map { row in
            [row.leading, row.trailing].compactMap { $0 }.joined(separator: "  ")
        }.joined(separator: "\n")
    }
}
