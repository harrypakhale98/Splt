import Foundation
import SpltCore

/// What a balance link carries: one group's balances at one moment, for a friend without the app.
///
/// It holds names, colors and amounts only. People are short indexes into `members`, so no id,
/// contact detail or iCloud identifier ever leaves the device. The one exception is an invite link,
/// made for one person who isn't on Splt yet: it adds the group's iCloud invite and that person's id,
/// so they can join as themselves. The web page at `docs/b/` reads the same layout, so a change here
/// needs a new `version` and a matching change there. A new optional key keeps the version, because
/// both sides already skip keys they don't know.
///
/// The JSON keys, all short to keep links short:
/// - `v` version, `n` group name, `d` trip days `[start, end]` as `yyyy-MM-dd` (optional)
/// - `c` currencies `[[code, minor unit digits]]`, the group's own first
/// - `m` members `[name, color index, paid in the group's currency, 1 if they left]`
/// - `x` who pays whom `[from, to, minor units, currency index]`
/// - `e` recent expenses, newest first (optional): `[title, yyyy-MM-dd, currency index, total,
///   [[payer, paid]], [[person, share]]]`
/// - `s` the member who shared it, or -1, and `t` the snapshot time in seconds since 1970
/// - `j` an invite (optional): `[iCloud invite link, the invited member, that member's id]`
struct BalanceSnapshot: Equatable, Sendable {
    static let version = 1
    /// The most recent expenses a link carries.
    static let expenseLimit = 10
    static let nameLimit = 40
    static let titleLimit = 60

    struct Currency: Equatable, Sendable {
        var code: String
        var digits: Int
    }

    struct Member: Equatable, Sendable {
        var name: String
        /// A hue from `PersonPalette`.
        var colorIndex: Int
        /// What they paid in the group's own currency, which sizes the strip.
        var paid: Int64
        /// Someone who left the group but still has money in it.
        var hasLeft = false
    }

    struct Transfer: Equatable, Sendable {
        var from: Int
        var to: Int
        var amount: Int64
        var currency: Int = 0
    }

    struct Part: Equatable, Sendable {
        var person: Int
        var amount: Int64
    }

    /// An invite for one member who isn't on Splt yet.
    struct Join: Equatable, Sendable {
        /// The group's iCloud invite, open to anyone with the link.
        var shareURL: URL
        /// The member it is for.
        var person: Int
        /// That member's id, so joining takes over the same person.
        var personID: UUID

        /// iCloud invite links are on icloud.com. Anything else is not one.
        static func isShareURL(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
            return (host == "icloud.com" || host.hasSuffix(".icloud.com")) && url.absoluteString.count <= 300
        }
    }

    struct ExpenseLine: Equatable, Sendable {
        var title: String
        var day: String
        var currency: Int
        var total: Int64
        var payers: [Part]
        var shares: [Part]
    }

    var groupName: String
    var tripDays: [String]?
    var currencies: [Currency]
    var members: [Member]
    var transfers: [Transfer]
    /// Nil when the person sharing left recent expenses out.
    var expenses: [ExpenseLine]?
    var sharedBy: Int
    /// Whole seconds, so a decoded snapshot equals the one encoded.
    var createdAt: Date
    /// Set only on an invite link.
    var join: Join? = nil
}

// MARK: Building

extension BalanceSnapshot {
    /// The snapshot of a group as its screen shows it now.
    init(
        group: SplitGroup,
        me: PersonID?,
        people: [PersonID: Person],
        expenses: [Expense],
        balances: GroupBalances?,
        includesExpenses: Bool,
        now: Date,
        calendar: Calendar = .current,
        invite: (shareURL: URL, person: PersonID)? = nil
    ) {
        let live = expenses.filter { !$0.isDeleted }
        let recent = includesExpenses
            ? Array(live.sorted { $0.date > $1.date }.prefix(Self.expenseLimit))
            : []
        let debts = balances?.suggestedSettlements ?? []
        let shares: [ExpenseID: [PersonID: Money]] = Dictionary(
            uniqueKeysWithValues: recent.compactMap { expense in
                (try? expense.shares().shares).map { (expense.id, $0) }
            }
        )

        // Members in the group's order, then anyone who left but still appears.
        var order: [PersonID] = []
        var seen = Set<PersonID>()
        func note(_ id: PersonID) {
            if seen.insert(id).inserted { order.append(id) }
        }
        group.memberIDs.forEach(note)
        debts.forEach { note($0.debtor); note($0.creditor) }
        for expense in recent where shares[expense.id] != nil {
            expense.payers.keys.sorted().forEach(note)
            shares[expense.id]?.keys.sorted().forEach(note)
        }
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let current = Set(group.memberIDs)
        let hues = PersonPalette.indices(for: group.memberIDs)
        let groupCode = group.currencyCode

        var paid: [PersonID: Int64] = [:]
        for expense in live where expense.total.currencyCode == groupCode {
            for (person, amount) in expense.payers where amount.minorUnits > 0 {
                paid[person, default: 0] &+= amount.minorUnits
            }
        }

        var codes = [groupCode]
        func currency(_ code: String) -> Int {
            if let found = codes.firstIndex(of: code) { return found }
            codes.append(code)
            return codes.count - 1
        }

        let members = order.map { id in
            Member(
                name: Self.clipped(people[id]?.name, limit: Self.nameLimit, fallback: String(localized: "Someone")),
                colorIndex: hues[id] ?? PersonPalette.index(for: id),
                paid: paid[id] ?? 0,
                hasLeft: !current.contains(id)
            )
        }
        let transfers = debts.compactMap { debt -> Transfer? in
            guard let from = index[debt.debtor], let to = index[debt.creditor] else { return nil }
            return Transfer(from: from, to: to, amount: debt.amount.minorUnits, currency: currency(debt.amount.currencyCode))
        }
        let lines = recent.compactMap { expense -> ExpenseLine? in
            guard let split = shares[expense.id] else { return nil }
            func parts(_ amounts: [PersonID: Money]) -> [Part] {
                amounts.compactMap { id, money in index[id].map { Part(person: $0, amount: money.minorUnits) } }
                    .sorted { $0.person < $1.person }
            }
            return ExpenseLine(
                title: Self.clipped(expense.title, limit: Self.titleLimit, fallback: String(localized: "Expense")),
                day: Self.day(expense.date, calendar: calendar),
                currency: currency(expense.total.currencyCode),
                total: expense.total.minorUnits,
                payers: parts(expense.payers),
                shares: parts(split)
            )
        }

        self.init(
            groupName: Self.clipped(group.name, limit: Self.titleLimit, fallback: String(localized: "Group")),
            tripDays: {
                guard let start = group.tripStart, let end = group.tripEnd else { return nil }
                return [Self.day(start, calendar: calendar), Self.day(max(start, end), calendar: calendar)]
            }(),
            currencies: codes.map { Currency(code: $0, digits: SpltCore.Currency.minorUnitExponent(for: $0)) },
            members: members,
            transfers: transfers,
            expenses: includesExpenses ? lines : nil,
            sharedBy: me.flatMap { index[$0] } ?? -1,
            createdAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)),
            join: invite.flatMap { invite in
                index[invite.person].map { Join(shareURL: invite.shareURL, person: $0, personID: invite.person.rawValue) }
            }
        )
    }

    /// Trimmed, on one line and no longer than `limit` characters.
    static func clipped(_ text: String?, limit: Int, fallback: String) -> String {
        let flat = (text ?? "").components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return fallback }
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// A calendar day as `yyyy-MM-dd`, read in the sharer's calendar so it never shifts a day.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }
}

// MARK: JSON

extension BalanceSnapshot: Codable {
    private enum Key: String, CodingKey {
        case v, n, d, c, m, x, e, s, t, j
    }

    enum FormatError: Error, Equatable {
        case unsupportedVersion(Int)
        case invalid(String)
    }

    func encode(to encoder: any Encoder) throws {
        var root = encoder.container(keyedBy: Key.self)
        try root.encode(Self.version, forKey: .v)
        try root.encode(groupName, forKey: .n)
        try root.encodeIfPresent(tripDays, forKey: .d)
        var currencyList = root.nestedUnkeyedContainer(forKey: .c)
        for currency in currencies {
            var item = currencyList.nestedUnkeyedContainer()
            try item.encode(currency.code)
            try item.encode(currency.digits)
        }
        var memberList = root.nestedUnkeyedContainer(forKey: .m)
        for member in members {
            var item = memberList.nestedUnkeyedContainer()
            try item.encode(member.name)
            try item.encode(member.colorIndex)
            try item.encode(member.paid)
            if member.hasLeft { try item.encode(1) }
        }
        var transferList = root.nestedUnkeyedContainer(forKey: .x)
        for transfer in transfers {
            var item = transferList.nestedUnkeyedContainer()
            try item.encode(transfer.from)
            try item.encode(transfer.to)
            try item.encode(transfer.amount)
            try item.encode(transfer.currency)
        }
        if let expenses {
            var expenseList = root.nestedUnkeyedContainer(forKey: .e)
            for expense in expenses {
                var item = expenseList.nestedUnkeyedContainer()
                try item.encode(expense.title)
                try item.encode(expense.day)
                try item.encode(expense.currency)
                try item.encode(expense.total)
                for parts in [expense.payers, expense.shares] {
                    var partList = item.nestedUnkeyedContainer()
                    for part in parts {
                        var pair = partList.nestedUnkeyedContainer()
                        try pair.encode(part.person)
                        try pair.encode(part.amount)
                    }
                }
            }
        }
        try root.encode(sharedBy, forKey: .s)
        try root.encode(Int64(createdAt.timeIntervalSince1970), forKey: .t)
        if let join {
            var item = root.nestedUnkeyedContainer(forKey: .j)
            try item.encode(join.shareURL.absoluteString)
            try item.encode(join.person)
            try item.encode(join.personID.uuidString)
        }
    }

    init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: Key.self)
        let version = try root.decode(Int.self, forKey: .v)
        guard version == Self.version else { throw FormatError.unsupportedVersion(version) }
        groupName = try root.decode(String.self, forKey: .n)
        tripDays = try root.decodeIfPresent([String].self, forKey: .d)

        currencies = []
        var currencyList = try root.nestedUnkeyedContainer(forKey: .c)
        while !currencyList.isAtEnd {
            var item = try currencyList.nestedUnkeyedContainer()
            currencies.append(Currency(code: try item.decode(String.self), digits: try item.decode(Int.self)))
        }
        members = []
        var memberList = try root.nestedUnkeyedContainer(forKey: .m)
        while !memberList.isAtEnd {
            var item = try memberList.nestedUnkeyedContainer()
            let name = try item.decode(String.self)
            let hue = try item.decode(Int.self)
            let paid = try item.decode(Int64.self)
            var left = 0
            if !item.isAtEnd { left = try item.decode(Int.self) }
            members.append(Member(name: name, colorIndex: hue, paid: paid, hasLeft: left == 1))
        }
        transfers = []
        var transferList = try root.nestedUnkeyedContainer(forKey: .x)
        while !transferList.isAtEnd {
            var item = try transferList.nestedUnkeyedContainer()
            transfers.append(Transfer(
                from: try item.decode(Int.self), to: try item.decode(Int.self),
                amount: try item.decode(Int64.self), currency: try item.decode(Int.self)
            ))
        }
        if root.contains(.e) {
            var lines: [ExpenseLine] = []
            var expenseList = try root.nestedUnkeyedContainer(forKey: .e)
            while !expenseList.isAtEnd {
                var item = try expenseList.nestedUnkeyedContainer()
                let title = try item.decode(String.self)
                let day = try item.decode(String.self)
                let currency = try item.decode(Int.self)
                let total = try item.decode(Int64.self)
                var partLists: [[Part]] = []
                for _ in 0..<2 {
                    var parts: [Part] = []
                    var partList = try item.nestedUnkeyedContainer()
                    while !partList.isAtEnd {
                        var pair = try partList.nestedUnkeyedContainer()
                        parts.append(Part(person: try pair.decode(Int.self), amount: try pair.decode(Int64.self)))
                    }
                    partLists.append(parts)
                }
                lines.append(ExpenseLine(
                    title: title, day: day, currency: currency, total: total,
                    payers: partLists[0], shares: partLists[1]
                ))
            }
            expenses = lines
        } else {
            expenses = nil
        }
        sharedBy = try root.decode(Int.self, forKey: .s)
        createdAt = Date(timeIntervalSince1970: TimeInterval(try root.decode(Int64.self, forKey: .t)))
        if root.contains(.j) {
            var item = try root.nestedUnkeyedContainer(forKey: .j)
            guard let url = URL(string: try item.decode(String.self)) else { throw FormatError.invalid("join") }
            let person = try item.decode(Int.self)
            guard let id = UUID(uuidString: try item.decode(String.self)) else { throw FormatError.invalid("join") }
            join = Join(shareURL: url, person: person, personID: id)
        } else {
            join = nil
        }
        try validate()
    }

    /// Every index points at something, so a reader never has to guess.
    func validate() throws {
        let people = members.indices
        guard !currencies.isEmpty, !members.isEmpty else { throw FormatError.invalid("empty") }
        guard sharedBy == -1 || people.contains(sharedBy) else { throw FormatError.invalid("sharer") }
        for transfer in transfers {
            guard people.contains(transfer.from), people.contains(transfer.to),
                  currencies.indices.contains(transfer.currency) else { throw FormatError.invalid("transfer") }
        }
        for expense in expenses ?? [] {
            guard currencies.indices.contains(expense.currency),
                  (expense.payers + expense.shares).allSatisfy({ people.contains($0.person) })
            else { throw FormatError.invalid("expense") }
        }
        if let join {
            guard people.contains(join.person), Join.isShareURL(join.shareURL) else { throw FormatError.invalid("join") }
        }
    }
}
