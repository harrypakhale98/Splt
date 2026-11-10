import Foundation
import Observation
import SpltCore

/// The state behind the new group sheet.
@MainActor
@Observable
final class CreateGroupViewModel {
    var name = ""
    private(set) var template: GroupTemplate = .standard
    private(set) var symbol = GroupTemplate.standard.defaultSymbol
    var currencyCode: String
    var tripStart: Date
    var tripEnd: Date
    var simplifiesDebts = true
    private(set) var members: [MemberDraft] = []
    private(set) var friends: [Person] = []
    /// You, when you are already set up, so your own disc can lead the member list.
    private(set) var me: Person?

    @ObservationIgnored private let groups: any GroupRepository
    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private var symbolWasChosen = false

    init(
        services: DataServices,
        defaultCurrencyCode: String,
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        groups = services.groups
        people = services.people
        currencyCode = defaultCurrencyCode
        let start = calendar.startOfDay(for: today)
        tripStart = start
        tripEnd = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        friends = (try? people.friends()) ?? []
        me = try? people.me()
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCreate: Bool {
        !trimmedName.isEmpty && (template != .trip || tripEnd >= tripStart)
    }

    // MARK: Appearance

    func selectTemplate(_ newValue: GroupTemplate) {
        template = newValue
        applyAutomaticSymbol()
    }

    /// Call when the name changes. A symbol the person picked is never replaced.
    func nameChanged() {
        applyAutomaticSymbol()
    }

    func chooseSymbol(_ newValue: String) {
        symbol = newValue
        symbolWasChosen = true
    }

    /// Keeps the end date from falling before the start date.
    func tripStartChanged() {
        if tripEnd < tripStart { tripEnd = tripStart }
    }

    private func applyAutomaticSymbol() {
        guard !symbolWasChosen else { return }
        symbol = GroupSymbolSuggester.symbol(for: name) ?? template.defaultSymbol
    }

    // MARK: Members

    /// Adds a person by name. Returns false for a blank name or one that is already on the list.
    @discardableResult
    func addMember(named rawName: String, contactHint: String? = nil) -> Bool {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !containsName(trimmed) else { return false }
        members.append(MemberDraft(name: trimmed, contactHint: contactHint))
        return true
    }

    func addContacts(_ drafts: [MemberDraft]) {
        for draft in drafts {
            addMember(named: draft.name, contactHint: draft.contactHint)
        }
    }

    func isSelected(_ person: Person) -> Bool {
        members.contains { $0.existingID == person.id }
    }

    func toggle(_ person: Person) {
        if let index = members.firstIndex(where: { $0.existingID == person.id }) {
            members.remove(at: index)
        } else {
            members.append(MemberDraft(person: person))
        }
    }

    func removeMembers(at offsets: IndexSet) {
        members.remove(atOffsets: offsets)
    }

    private func containsName(_ candidate: String) -> Bool {
        members.contains { $0.name.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    // MARK: Saving

    /// Creates the group with you and the listed people in it. People without the app become placeholders.
    func create() throws -> GroupID {
        let me = try people.me() ?? people.ensureMe(name: String(localized: "You"))
        var memberIDs = [me.id]
        for draft in members {
            let id: PersonID
            if let existing = draft.existingID {
                id = existing
            } else {
                let person = Person(name: draft.name, contactHint: draft.contactHint, kind: .placeholder)
                try people.add(person)
                id = person.id
            }
            if !memberIDs.contains(id) { memberIDs.append(id) }
        }
        let isTrip = template == .trip
        let group = SplitGroup(
            name: trimmedName,
            symbol: symbol,
            currencyCode: currencyCode,
            kind: template.kind,
            memberIDs: memberIDs,
            simplifiesDebts: simplifiesDebts,
            tripStart: isTrip ? tripStart : nil,
            tripEnd: isTrip ? tripEnd : nil
        )
        try groups.create(group)
        return group.id
    }
}
