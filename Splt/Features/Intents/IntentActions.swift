import Foundation
import SpltCore

/// The work behind the intents, kept apart from the App Intents types so it can be tested.
@MainActor
struct IntentActions {
    enum Failure: Error, Equatable {
        case noStorage
        case noGroup
        case badAmount
        case unknownFriend
        case unknownGroup
        case saveFailed
    }

    struct AddedExpense: Equatable {
        var title: String
        var amount: Money
        var groupName: String
    }

    let services: DataServices
    var now: @Sendable () -> Date = { Date() }
    var leftGroups = LeftGroupsStore()

    // MARK: Add expense

    /// Records an expense you paid and split equally with everyone in the group, or with one friend.
    @discardableResult
    func addExpense(title: String, amount: Double, group: UUID?, friend: UUID?) throws -> AddedExpense {
        let me = try services.people.me() ?? services.people.ensureMe(name: String(localized: "You"))
        let target = try targetGroup(group: group, friend: friend)
        guard let total = IntentAmount.money(from: amount, currencyCode: target.currencyCode) else {
            throw Failure.badAmount
        }
        let cleaned = title.tidied
        let members = Set(target.memberIDs).union([me.id])
        let expense = Expense(
            groupID: target.id,
            title: cleaned.isEmpty ? String(localized: "Expense") : cleaned,
            total: total,
            date: now(),
            paidBy: me.id,
            split: .equal(participants: members)
        )
        do {
            try services.expenses.add(expense)
        } catch {
            throw Failure.saveFailed
        }
        return AddedExpense(title: expense.title, amount: total, groupName: SettleLeg.displayName(of: target))
    }

    private func targetGroup(group: UUID?, friend: UUID?) throws -> SplitGroup {
        if let group {
            guard let found = try services.groups.group(id: GroupID(rawValue: group)) else { throw Failure.unknownGroup }
            return found
        }
        if let friend {
            let id = PersonID(rawValue: friend)
            guard try services.people.person(id: id) != nil else { throw Failure.unknownFriend }
            let groupID = try DirectGroupResolver.group(with: id, services: services)
            guard let found = try services.groups.group(id: groupID) else { throw Failure.noGroup }
            return found
        }
        let groups = try services.groups.groups(includeArchived: false).filter { $0.kind != .friend && !leftGroups.contains($0.id) }
        guard let first = groups.first else { throw Failure.noGroup }
        return first
    }

    // MARK: Balance

    /// One sentence about what is owed with a friend, in a group, or overall.
    func balanceSentence(friend: UUID?, group: UUID?, locale: Locale = .current) throws -> String {
        if let friend {
            let id = PersonID(rawValue: friend)
            guard let person = try services.people.person(id: id) else { throw Failure.unknownFriend }
            return Self.sentence(about: person.name, amounts: try services.people.friendBalance(with: id).total, locale: locale)
        }
        if let group {
            let id = GroupID(rawValue: group)
            guard let found = try services.groups.group(id: id), let me = try services.people.me() else { throw Failure.unknownGroup }
            let net = try services.groups.balances(for: id).net(for: me.id)
            return Self.groupSentence(name: found.name, amounts: net, locale: locale)
        }
        services.friendsStore.refresh()
        return Self.overallSentence(services.friendsStore.totals, locale: locale)
    }

    static func sentence(about name: String, amounts: [Money], locale: Locale) -> String {
        let owed = list(amounts.filter(\.isPositive), locale: locale)
        let owing = list(amounts.filter(\.isNegative).map(Self.magnitude), locale: locale)
        switch (owed.isEmpty, owing.isEmpty) {
        case (true, true): return String(localized: "You and \(name) are settled up.")
        case (false, true): return String(localized: "\(name) owes you \(owed).")
        case (true, false): return String(localized: "You owe \(name) \(owing).")
        case (false, false): return String(localized: "\(name) owes you \(owed), and you owe \(name) \(owing).")
        }
    }

    static func groupSentence(name: String, amounts: [Money], locale: Locale) -> String {
        let owed = list(amounts.filter(\.isPositive), locale: locale)
        let owing = list(amounts.filter(\.isNegative).map(Self.magnitude), locale: locale)
        switch (owed.isEmpty, owing.isEmpty) {
        case (true, true): return String(localized: "You are settled up in \(name).")
        case (false, true): return String(localized: "In \(name), you are owed \(owed).")
        case (true, false): return String(localized: "In \(name), you owe \(owing).")
        case (false, false): return String(localized: "In \(name), you are owed \(owed) and owe \(owing).")
        }
    }

    static func overallSentence(_ totals: BalanceTotals, locale: Locale) -> String {
        let owed = list(totals.owedToYou, locale: locale)
        let owing = list(totals.youOwe, locale: locale)
        switch (owed.isEmpty, owing.isEmpty) {
        case (true, true): return String(localized: "You are all settled up.")
        case (false, true): return String(localized: "Friends owe you \(owed).")
        case (true, false): return String(localized: "You owe friends \(owing).")
        case (false, false): return String(localized: "Friends owe you \(owed), and you owe \(owing).")
        }
    }

    private static func magnitude(_ money: Money) -> Money {
        Money(minorUnits: abs(money.minorUnits), currencyCode: money.currencyCode)
    }

    private static func list(_ amounts: [Money], locale: Locale) -> String {
        ListFormatter.localizedString(byJoining: amounts.map { MoneyFormatting.magnitudeString($0, locale: locale) })
    }
}

enum IntentAmount {
    /// An amount typed or spoken as a number, rounded to the currency's smallest unit. Nil if it is not a positive amount.
    static func money(from value: Double, currencyCode: String) -> Money? {
        guard value.isFinite, value > 0, value < 1e12 else { return nil }
        let exponent = Currency.minorUnitExponent(for: currencyCode)
        guard let parsed = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var scaled = parsed * Decimal(sign: .plus, exponent: exponent, significand: 1)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let units = NSDecimalNumber(decimal: rounded).int64Value
        guard units > 0 else { return nil }
        return Money(minorUnits: units, currencyCode: currencyCode)
    }
}
