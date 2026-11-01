import Foundation
import Observation
import SpltCore

/// The state behind the group settings sheet. Text fields and dates are saved together with `save()`;
/// members, archive, leave and delete act straight away.
@MainActor
@Observable
final class GroupSettingsViewModel {
    struct MemberRow: Identifiable, Equatable {
        var person: Person
        var isMe: Bool
        /// Positive means the person is owed. Empty when square.
        var balance: [Money]

        var id: PersonID { person.id }
        var canRemove: Bool { !isMe && balance.isEmpty }
    }

    let groupID: GroupID

    var name = ""
    var currencyCode = ""
    var tripStart = Date()
    var tripEnd = Date()
    var pinsRate = false
    /// The other currency of the pinned rate: one unit of it is worth `rateText` of the group currency.
    var rateCurrencyCode = ""
    var rateText = ""
    var locale: Locale = .current
    var errorMessage: String?
    var blockedMessage: String?

    private(set) var group: SplitGroup?
    private(set) var symbol = ""
    private(set) var memberRows: [MemberRow] = []
    private(set) var friendsToAdd: [Person] = []
    private(set) var didLoad = false

    @ObservationIgnored private let groups: any GroupRepository
    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private let expenses: any ExpenseRepository
    @ObservationIgnored private let payments: any PaymentRepository
    @ObservationIgnored private let now: @Sendable () -> Date

    init(groupID: GroupID, services: DataServices, now: @escaping @Sendable () -> Date = { Date() }) {
        self.groupID = groupID
        groups = services.groups
        people = services.people
        expenses = services.expenses
        payments = services.payments
        self.now = now
        load()
    }

    private func load() {
        do {
            guard let loaded = try groups.group(id: groupID) else {
                didLoad = true
                return
            }
            group = loaded
            name = loaded.name
            symbol = loaded.symbol
            currencyCode = loaded.currencyCode
            tripStart = loaded.tripStart ?? Date()
            tripEnd = loaded.tripEnd ?? loaded.tripStart ?? Date()
            if let pinned = loaded.pinnedRate {
                pinsRate = true
                rateCurrencyCode = pinned.from == loaded.currencyCode ? pinned.to : pinned.from
                rateText = RateInput.string(pinned.rate, locale: locale)
            } else {
                rateCurrencyCode = Self.suggestedRateCurrency(excluding: loaded.currencyCode)
            }
            try reloadMembers()
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
        }
        didLoad = true
    }

    /// Re-reads members and their balances after a change.
    private func reloadMembers() throws {
        guard let current = try groups.group(id: groupID) else { return }
        group = current
        let me = try people.me()?.id
        let balances = try groups.balances(for: groupID)
        memberRows = try people.people(ids: current.memberIDs).map { person in
            MemberRow(person: person, isMe: person.id == me, balance: balances.net(for: person.id))
        }
        let members = Set(current.memberIDs)
        friendsToAdd = try people.friends().filter { !members.contains($0.id) }
    }

    private static func suggestedRateCurrency(excluding code: String) -> String {
        let candidate = Preferences.systemCurrencyCode
        return candidate == code ? (code == "USD" ? "EUR" : "USD") : candidate
    }

    // MARK: Fields

    var isTrip: Bool { group?.kind == .trip }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var rate: Decimal? {
        RateInput.parse(rateText, locale: locale)
    }

    var canSave: Bool {
        guard !trimmedName.isEmpty else { return false }
        if isTrip, tripEnd < tripStart { return false }
        if isTrip, pinsRate, rate == nil || rateCurrencyCode == currencyCode { return false }
        return true
    }

    func chooseSymbol(_ value: String) {
        symbol = value
    }

    func tripStartChanged() {
        if tripEnd < tripStart { tripEnd = tripStart }
    }

    /// Saves the name, symbol, currency, trip dates and pinned rate.
    func save() throws {
        guard var edited = group, canSave else { return }
        edited.name = trimmedName
        edited.symbol = symbol
        edited.currencyCode = currencyCode.uppercased()
        if isTrip {
            edited.tripStart = tripStart
            edited.tripEnd = tripEnd
            if pinsRate, let rate {
                edited.pinnedRate = PinnedRate(from: rateCurrencyCode, to: edited.currencyCode, rate: rate)
            } else {
                edited.pinnedRate = nil
            }
        }
        try groups.update(edited)
        group = edited
    }

    // MARK: Members

    func removalBlock(for row: MemberRow) -> String? {
        guard !row.balance.isEmpty else { return nil }
        let amounts = row.balance.map { MoneyFormatting.magnitudeString($0, locale: locale) }.joined(separator: ", ")
        let name = row.person.name
        return row.balance.contains { $0.minorUnits > 0 }
            ? String(localized: "\(name) is owed \(amounts) in this group. Settle up before removing them.")
            : String(localized: "\(name) owes \(amounts) in this group. Settle up before removing them.")
    }

    /// Removes the person if they are square, otherwise explains why not.
    func remove(_ row: MemberRow) {
        guard !row.isMe else { return }
        if let reason = removalBlock(for: row) {
            blockedMessage = reason
            return
        }
        perform { try groups.removeMember(row.person.id, from: groupID) }
    }

    func addMember(named rawName: String, contactHint: String? = nil) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform {
            let person = Person(name: trimmed, contactHint: contactHint, kind: .placeholder)
            try people.add(person)
            try groups.addMember(person.id, to: groupID)
        }
    }

    func addMember(_ person: Person) {
        perform { try groups.addMember(person.id, to: groupID) }
    }

    // MARK: Group actions

    var myRow: MemberRow? { memberRows.first(where: \.isMe) }

    /// Leaving needs you to be square and someone else to stay behind.
    var leaveBlock: String? {
        guard let myRow else { return String(localized: "You are not a member of this group.") }
        if memberRows.count < 2 { return String(localized: "You are the only member. Delete the group instead.") }
        if !myRow.balance.isEmpty {
            let amounts = myRow.balance.map { MoneyFormatting.magnitudeString($0, locale: locale) }.joined(separator: ", ")
            return myRow.balance.contains { $0.minorUnits > 0 }
                ? String(localized: "You are owed \(amounts). Settle up before leaving.")
                : String(localized: "You owe \(amounts). Settle up before leaving.")
        }
        return nil
    }

    /// Returns true when you left.
    func leave(using sharing: any GroupSharing) async -> Bool {
        guard leaveBlock == nil, let myRow else {
            blockedMessage = leaveBlock
            return false
        }
        try? await sharing.leave(groupID: groupID)
        do {
            try groups.removeMember(myRow.person.id, from: groupID)
            return true
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
            return false
        }
    }

    func toggleArchived() {
        guard let group else { return }
        perform { try groups.setArchived(!group.isArchived, id: groupID) }
    }

    /// Returns true when the group was deleted.
    func delete() -> Bool {
        do {
            try groups.delete(id: groupID)
            return true
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
            return false
        }
    }

    // MARK: Export

    func report() throws -> GroupReport {
        guard let group = try groups.group(id: groupID) else { throw DataError.notFound("group \(groupID)") }
        let everyone = Dictionary(try people.allPeople().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return GroupReport(
            group: group,
            people: everyone,
            expenses: try expenses.expenses(in: groupID, includeDeleted: false),
            payments: try payments.payments(in: groupID),
            balances: try groups.balances(for: groupID),
            generatedAt: now()
        )
    }

    /// Writes the spreadsheet and the PDF for sharing.
    func exportFiles() throws -> GroupExportFiles {
        let csv = try groups.export(group: groupID, format: .csv)
        let report = try report()
        let pdf = GroupPDFRenderer.data(for: report, locale: locale)
        return try GroupExportFiles.write(csv: csv, pdf: pdf, groupName: report.groupName)
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            try reloadMembers()
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
        }
    }
}
