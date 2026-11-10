import Foundation
import Observation
import SpltCore

/// The state behind the group settings sheet. Text fields and dates are saved together with `save()`,
/// which the sheet's one button, Done, calls; members, archive, leave and delete act straight away.
@MainActor
@Observable
final class GroupSettingsViewModel {
    struct MemberRow: Identifiable, Equatable {
        var person: Person
        var isMe: Bool
        /// Positive means the person is owed. Empty when square.
        var balance: [Money]
        /// False when the net is zero but debts with single members remain, in a group that does
        /// not simplify debts.
        var isSquare = true
        /// A recurring expense that would keep charging the person, which has to change first.
        var recurringExpense: String?

        var id: PersonID { person.id }
        var canRemove: Bool { !isMe && balance.isEmpty && isSquare && recurringExpense == nil }
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
    /// Why you can't leave, shown under its own title.
    var leaveBlockedMessage: String?

    private(set) var group: SplitGroup?
    private(set) var symbol = ""
    private(set) var memberRows: [MemberRow] = []
    private(set) var friendsToAdd: [Person] = []
    /// Everyone you split with, in the group or not, for the friend picker.
    private(set) var friends: [Person] = []
    private(set) var didLoad = false

    @ObservationIgnored private let groups: any GroupRepository
    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private let expenses: any ExpenseRepository
    @ObservationIgnored private let payments: any PaymentRepository
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let leftGroups: LeftGroupsStore

    init(
        groupID: GroupID,
        services: DataServices,
        leftGroups: LeftGroupsStore = LeftGroupsStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.groupID = groupID
        self.leftGroups = leftGroups
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
            MemberRow(
                person: person, isMe: person.id == me, balance: balances.net(for: person.id),
                isSquare: balances.isSquare(person.id),
                recurringExpense: try groups.recurringExpenseTitle(involving: person.id, in: groupID)
            )
        }
        let members = Set(current.memberIDs)
        friends = try people.friends()
        friendsToAdd = friends.filter { !members.contains($0.id) }
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

    /// True when a field differs from what is saved, so the sheet isn't swiped away with the edit lost.
    var hasFieldEdits: Bool {
        guard let group else { return false }
        if trimmedName != group.name || symbol != group.symbol || currencyCode.uppercased() != group.currencyCode {
            return true
        }
        guard isTrip else { return false }
        if let start = group.tripStart, start != tripStart { return true }
        if let end = group.tripEnd, end != tripEnd { return true }
        if pinsRate != (group.pinnedRate != nil) { return true }
        if let pinned = group.pinnedRate, pinsRate {
            let other = pinned.from == group.currencyCode ? pinned.to : pinned.from
            return other != rateCurrencyCode || rate != pinned.rate
        }
        return false
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
        invalidateExports()
        group = edited
    }

    // MARK: Members

    func removalBlock(for row: MemberRow) -> String? {
        guard !row.balance.isEmpty else {
            let name = row.person.name
            if !row.isSquare {
                return String(localized: "\(name) still has debts with other members. Settle up before removing them.")
            }
            return row.recurringExpense.map {
                String(localized: "\(name) is part of the recurring expense “\($0)”. Change or delete it before removing them.")
            }
        }
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
        let same = { (person: Person) in
            person.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if let member = memberRows.first(where: { same($0.person) }) {
            errorMessage = String(localized: "\(member.person.name) is already in this group.")
            return
        }
        // the same name as a friend is that friend, as everywhere else people are added
        if let friend = friendsToAdd.first(where: same) {
            addMember(friend)
            return
        }
        perform {
            let person = Person(name: trimmed, contactHint: contactHint, kind: .placeholder)
            try people.add(person)
            try groups.addMember(person.id, to: groupID)
        }
    }

    func addMember(_ person: Person) {
        perform { try groups.addMember(person.id, to: groupID) }
    }

    func isMember(_ person: Person) -> Bool {
        memberRows.contains { $0.id == person.id }
    }

    /// Adds a friend from the picker. Removing stays a swipe on the member list, where a
    /// "settle up first" message can be seen; the picker sits over it and would hide that alert.
    func toggleFriend(_ person: Person) {
        guard !isMember(person) else { return }
        addMember(person)
    }

    // MARK: Group actions

    var myRow: MemberRow? { memberRows.first(where: \.isMe) }

    /// Set by `loadSharing`.
    private(set) var isSharedByMe = false
    /// True when someone else shared the group with you. Nil until `loadSharing` has answered.
    private(set) var isSharedWithMe: Bool?

    /// You leave a group you joined. One of your own stays in your iCloud, so leaving it would
    /// only hide it on this device.
    var canLeave: Bool { isSharedWithMe == true }
    /// You delete a group of your own. Deleting one you joined would only leave it, without the
    /// settle up check and with you still on the others' member list.
    var canDelete: Bool { isSharedWithMe == false }

    /// Leaving needs the group to be someone else's, you to be square and someone to stay behind.
    var leaveBlock: String? {
        guard let myRow else { return String(localized: "You are not a member of this group.") }
        if isSharedByMe {
            return String(localized: "You shared this group, so you can't leave it. Stop sharing in Invite with iCloud to keep it just for you, or delete it to remove it for everyone.")
        }
        if !canLeave {
            return String(localized: "You can only leave a group someone else shared with you. Delete this group instead.")
        }
        if memberRows.count < 2 { return String(localized: "You are the only member. Delete the group instead.") }
        if !myRow.balance.isEmpty {
            let amounts = myRow.balance.map { MoneyFormatting.magnitudeString($0, locale: locale) }.joined(separator: ", ")
            return myRow.balance.contains { $0.minorUnits > 0 }
                ? String(localized: "You're owed \(amounts). Settle up before leaving.")
                : String(localized: "You owe \(amounts). Settle up before leaving.")
        }
        if !myRow.isSquare {
            return String(localized: "You still have debts with other members. Settle up before leaving.")
        }
        if let title = myRow.recurringExpense {
            return String(localized: "You are part of the recurring expense “\(title)”. Change or delete it before leaving.")
        }
        return nil
    }

    /// Finds out whose group this is, which decides between leaving and deleting.
    func loadSharing(using sharing: any GroupSharing) async {
        isSharedWithMe = await sharing.groupsSharedWithMe().contains(groupID)
        isSharedByMe = await sharing.isSharedByMe(groupID: groupID)
    }

    /// Returns true when you left.
    func leave(using sharing: any GroupSharing) async -> Bool {
        await loadSharing(using: sharing)
        guard leaveBlock == nil, let myRow else {
            leaveBlockedMessage = leaveBlock
            return false
        }
        do {
            // first, because sync hides the group once it has left, and the others need to see this
            try groups.removeMember(myRow.person.id, from: groupID)
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
            return false
        }
        leftGroups.insert(groupID)
        try? await sharing.leave(groupID: groupID)
        return true
    }

    func toggleArchived() {
        guard let group else { return }
        perform { try groups.setArchived(!group.isArchived, id: groupID) }
    }

    /// Returns true when the group was deleted.
    func delete() -> Bool {
        if canLeave {
            errorMessage = String(localized: "You joined this group, so you can't delete it. Leave it instead.")
            return false
        }
        do {
            try groups.delete(id: groupID)
            return true
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
            return false
        }
    }

    // MARK: Export

    private(set) var exportStates: [GroupExportKind: GroupExportState] = [:]
    /// Where export files are written. Tests point it somewhere else.
    @ObservationIgnored var exportDirectory = GroupExportFile.defaultDirectory

    func exportState(_ kind: GroupExportKind) -> GroupExportState {
        exportStates[kind] ?? .idle
    }

    func report() throws -> GroupReport {
        guard let group = try groups.group(id: groupID) else { throw DataError.notFound("group \(groupID)") }
        let everyone = Dictionary(try people.allPeople().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return GroupReport(
            group: group,
            people: everyone,
            expenses: try expenses.expenses(in: groupID, includeDeleted: false),
            payments: try payments.payments(in: groupID),
            balances: try groups.balances(for: groupID),
            exportedAt: now()
        )
    }

    /// Builds one export when asked. The data is read here and the file is drawn and written off the
    /// main actor. The state shows progress, the finished file or why it failed.
    func prepareExport(_ kind: GroupExportKind) async {
        if exportState(kind) == .preparing { return }
        exportStates[kind] = .preparing
        do {
            let url = try await exportJob(kind).run()
            exportStates[kind] = .ready(url)
        } catch {
            exportStates[kind] = .failed(GroupErrorMessage.exportText(for: error))
        }
    }

    private func exportJob(_ kind: GroupExportKind) throws -> GroupExportJob {
        let content: GroupExportJob.Content
        let name: String
        if let format = kind.format {
            content = .data(try groups.export(group: groupID, format: format))
            name = try groups.group(id: groupID)?.name ?? ""
        } else {
            let report = try report()
            content = .pdf(report, locale)
            name = report.groupName
        }
        return GroupExportJob(content: content, groupName: name, fileExtension: kind.fileExtension, directory: exportDirectory)
    }

    /// Shared files no longer match once the group changes.
    private func invalidateExports() {
        exportStates = [:]
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            invalidateExports()
            try reloadMembers()
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
        }
    }
}
