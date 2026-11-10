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
        /// The labels over a table's figure columns.
        case columns
        /// A table line: a name, then one figure per column.
        case tableRow
        /// The closing line of a table, adding up each column.
        case tableTotal
    }

    var style: Style
    var leading: String
    var trailing: String?
    /// The figure columns of a table line, left to right.
    var columns: [String]

    init(_ style: Style, _ leading: String = "", trailing: String? = nil, columns: [String] = []) {
        self.style = style
        self.leading = leading
        self.trailing = trailing
        self.columns = columns
    }
}

/// What a group looks like on paper: who owes whom, then every expense and payment.
struct GroupReport: Equatable, Sendable {
    struct ExpenseLine: Equatable, Sendable {
        var date: Date
        var title: String
        var paidBy: String
        /// Signed: a refund is negative.
        var amount: Money

        var isRefund: Bool { amount.isNegative }
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
        /// Someone who left the group but still has money in it.
        var isFormer: Bool = false
    }

    /// Paid, share and net per person in one currency, so a reader can check the sums by hand:
    /// paid and share each add up to what was spent, and net adds up to zero.
    struct PersonTable: Equatable, Sendable {
        struct Line: Equatable, Sendable {
            var name: String
            var isFormer: Bool
            var paid: Money
            var share: Money
            /// Payments sent (positive) minus payments received.
            var settled: Money
            /// Paid minus share plus settled: the person's balance.
            var net: Money
        }

        var currencyCode: String
        var lines: [Line]
        /// Whether any payment was made in this currency, so the settled column is worth printing.
        var hasPayments: Bool

        func total(_ column: KeyPath<Line, Money>) -> Money {
            let sum = lines.reduce(Int128(0)) { $0 + Int128($1[keyPath: column].minorUnits) }
            return Money(minorUnits: Int64(clamping: sum), currencyCode: currencyCode)
        }
    }

    var groupName: String
    var currencyCode: String
    var exportedAt: Date
    var members: [MemberBalance]
    var transfers: [TransferLine]
    var expenses: [ExpenseLine]
    var payments: [PaymentLine]
    var totals: [Money]
    var people: [PersonTable]

    init(
        group: SplitGroup,
        people: [PersonID: Person],
        expenses: [Expense],
        payments: [Payment],
        balances: GroupBalances,
        exportedAt: Date
    ) {
        func name(_ id: PersonID) -> String { people[id]?.name ?? String(localized: "Someone") }
        let memberIDs = Set(group.memberIDs)
        groupName = group.name
        currencyCode = group.currencyCode
        self.exportedAt = exportedAt

        // Current members, then anyone who left but still owes or is owed, so the balances add up to zero.
        let former = Set(balances.netBalances.values.flatMap { byPerson in
            byPerson.filter { !$0.value.isZero }.keys
        }).subtracting(memberIDs)
        let formerIDs = former.sorted { (name($0), $0.description) < (name($1), $1.description) }
        members = (group.memberIDs + formerIDs).map { id in
            MemberBalance(
                name: name(id),
                amounts: BalanceLine.lines(for: balances.net(for: id)).map(\.money),
                isFormer: !memberIDs.contains(id)
            )
        }
        transfers = balances.suggestedSettlements.map {
            TransferLine(from: name($0.debtor), to: name($0.creditor), amount: $0.amount)
        }
        let live = expenses.filter { !$0.isDeleted }
        let livePayments = payments.filter { !$0.isDeleted }
        self.expenses = live.sorted { $0.date < $1.date }.map { expense in
            let payers = expense.payers.keys.sorted().map(name).joined(separator: ", ")
            return ExpenseLine(date: expense.date, title: expense.title, paidBy: payers, amount: expense.total)
        }
        self.payments = livePayments.sorted { $0.date < $1.date }.map {
            PaymentLine(date: $0.date, from: name($0.payer), to: name($0.receiver), amount: $0.amount)
        }
        totals = GroupTotals.make(expenses: live, names: [:]).map(\.total)
        self.people = Self.personTables(
            expenses: live, payments: livePayments, members: group.memberIDs, name: name
        )
    }

    /// One table per currency, the group's own currency first. Only entries the ledger counts are
    /// added, so the net column matches the balances.
    private static func personTables(
        expenses: [Expense], payments: [Payment], members: [PersonID], name: (PersonID) -> String
    ) -> [PersonTable] {
        struct Sums { var paid: Int128 = 0; var share: Int128 = 0; var settled: Int128 = 0 }
        var byCurrency: [String: [PersonID: Sums]] = [:]
        var paymentCurrencies = Set<String>()

        for expense in expenses {
            guard (try? expense.netBalances()) != nil, let shares = try? expense.shares().shares else { continue }
            let code = expense.total.currencyCode
            var table = byCurrency[code, default: [:]]
            for (person, amount) in expense.payers { table[person, default: Sums()].paid += Int128(amount.minorUnits) }
            for (person, amount) in shares { table[person, default: Sums()].share += Int128(amount.minorUnits) }
            byCurrency[code] = table
        }
        for payment in payments {
            guard (try? payment.validate()) != nil else { continue }
            let code = payment.amount.currencyCode
            let units = Int128(payment.amount.minorUnits)
            var table = byCurrency[code, default: [:]]
            table[payment.payer, default: Sums()].settled += units
            table[payment.receiver, default: Sums()].settled -= units
            byCurrency[code] = table
            paymentCurrencies.insert(code)
        }

        let memberSet = Set(members)
        return byCurrency.map { code, table -> PersonTable in
            func money(_ value: Int128) -> Money { Money(minorUnits: Int64(clamping: value), currencyCode: code) }
            let others = table.keys.filter { !memberSet.contains($0) }
                .sorted { (name($0), $0.description) < (name($1), $1.description) }
            let lines = (members + others).map { id -> PersonTable.Line in
                let sums = table[id] ?? Sums()
                return PersonTable.Line(
                    name: name(id), isFormer: !memberSet.contains(id),
                    paid: money(sums.paid), share: money(sums.share), settled: money(sums.settled),
                    net: money(sums.paid - sums.share + sums.settled)
                )
            }
            return PersonTable(currencyCode: code, lines: lines, hasPayments: paymentCurrencies.contains(code))
        }
        .sorted { lhs, rhs in
            let lhsSpent = lhs.total(\.paid).minorUnits.magnitude
            let rhsSpent = rhs.total(\.paid).minorUnits.magnitude
            return lhsSpent == rhsSpent ? lhs.currencyCode < rhs.currencyCode : lhsSpent > rhsSpent
        }
    }

    /// An amount with its sign, so a refund never reads as spending: "−$24.00".
    static func signedString(_ money: Money, locale: Locale) -> String {
        let magnitude = MoneyFormatting.magnitudeString(money, locale: locale)
        return money.minorUnits < 0 ? "\u{2212}" + magnitude : magnitude
    }

    /// The report as rows, shared by the PDF and the plain text so they always agree.
    func rows(locale: Locale = .current) -> [ReportRow] {
        func money(_ value: Money) -> String { Self.signedString(value, locale: locale) }
        func day(_ date: Date) -> String { date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)) }
        func person(_ name: String, isFormer: Bool) -> String {
            isFormer ? String(localized: "\(name) (left)") : name
        }

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
            let label = person(member.name, isFormer: member.isFormer)
            if member.amounts.isEmpty {
                rows.append(ReportRow(.body, label, trailing: String(localized: "Settled up")))
            } else {
                for amount in member.amounts {
                    let value = MoneyFormatting.magnitudeString(amount, locale: locale)
                    let text = amount.minorUnits > 0
                        ? String(localized: "is owed \(value)")
                        : String(localized: "owes \(value)")
                    rows.append(ReportRow(.body, label, trailing: text))
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

        if !people.isEmpty {
            rows.append(ReportRow(.heading, String(localized: "By Person")))
            for (index, table) in people.enumerated() {
                if index > 0 { rows.append(ReportRow(.spacer)) }
                var labels = [String(localized: "Paid"), String(localized: "Share")]
                if table.hasPayments { labels.append(String(localized: "Settled")) }
                labels.append(String(localized: "Net"))
                rows.append(ReportRow(.columns, people.count > 1 ? table.currencyCode : "", columns: labels))
                func figures(_ paid: Money, _ share: Money, _ settled: Money, _ net: Money) -> [String] {
                    (table.hasPayments ? [paid, share, settled, net] : [paid, share, net]).map(money)
                }
                for line in table.lines {
                    rows.append(ReportRow(
                        .tableRow, person(line.name, isFormer: line.isFormer),
                        columns: figures(line.paid, line.share, line.settled, line.net)
                    ))
                }
                rows.append(ReportRow(
                    .tableTotal, String(localized: "Total"),
                    columns: figures(table.total(\.paid), table.total(\.share), table.total(\.settled), table.total(\.net))
                ))
            }
            rows.append(ReportRow(.spacer))
        }

        rows.append(ReportRow(.heading, String(localized: "Expenses")))
        if expenses.isEmpty {
            rows.append(ReportRow(.body, String(localized: "No expenses")))
        }
        for expense in expenses {
            rows.append(ReportRow(.body, expense.title, trailing: money(expense.amount)))
            let who = expense.isRefund
                ? String(localized: "refund received by \(expense.paidBy)")
                : String(localized: "paid by \(expense.paidBy)")
            rows.append(ReportRow(.caption, "\(day(expense.date)), \(who)"))
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
            ([row.leading] + [row.trailing].compactMap { $0 } + row.columns)
                .filter { !$0.isEmpty || row.columns.isEmpty }
                .joined(separator: "  ")
        }.joined(separator: "\n")
    }
}
