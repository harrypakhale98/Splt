import Foundation
import SpltCore

/// A field's value before or after an edit, stored without anything that depends on the device
/// that made the edit: amounts in minor units with their currency code, dates in ISO 8601, the
/// category's raw value and people by id. Names, currency symbols and date formats are applied
/// when the change is shown. Each field fills only the parts it needs.
struct ExpenseChangeValue: Hashable, Sendable, Codable {
    /// A title, note, category raw value, location name, repeat frequency raw value or split kind.
    var text: String?
    var minorUnits: Int64?
    var currencyCode: String?
    /// ISO 8601.
    var date: String?
    /// Payers, or the people in a split, by id.
    var people: [UUID]?
    /// What each payer put in, in minor units of `currencyCode`, keyed by the person's id.
    var amounts: [String: Int64]?
    /// A group's id.
    var id: UUID?

    init(
        text: String? = nil, minorUnits: Int64? = nil, currencyCode: String? = nil, date: String? = nil,
        people: [UUID]? = nil, amounts: [String: Int64]? = nil, id: UUID? = nil
    ) {
        self.text = text
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
        self.date = date
        self.people = people
        self.amounts = amounts
        self.id = id
    }

    var money: Money? {
        guard let minorUnits, let currencyCode else { return nil }
        return Money(minorUnits: minorUnits, currencyCode: currencyCode)
    }

    var dateValue: Date? {
        date.flatMap { try? Date($0, strategy: .iso8601) }
    }

    var personIDs: [PersonID] {
        (people ?? []).map { PersonID(rawValue: $0) }
    }

    /// Each payer with what they put in, in the order the ids are stored.
    var payments: [(person: PersonID, amount: Money)] {
        guard let currencyCode else { return [] }
        return personIDs.compactMap { person in
            amounts?[person.rawValue.uuidString].map { (person, Money(minorUnits: $0, currencyCode: currencyCode)) }
        }
    }
}

/// One field an edit changed. A nil side means the field was empty: a receipt added has no
/// `before`, a repeat turned off has no `after`.
struct ExpenseChange: Hashable, Sendable, Codable {
    var field: ExpenseField
    var before: ExpenseChangeValue?
    var after: ExpenseChangeValue?
}

/// The changes one edit made. Encoded as a plain list. Reading skips a change it cannot read,
/// such as a field a later version adds, so one unknown change never hides the whole event.
struct ExpenseChanges: Hashable, Sendable, Codable {
    var list: [ExpenseChange]

    init(_ list: [ExpenseChange]) {
        self.list = list
    }

    init(from decoder: any Decoder) throws {
        list = []
        guard var container = try? decoder.unkeyedContainer() else { return }
        while !container.isAtEnd {
            if let change = try? container.decode(ExpenseChange.self) {
                list.append(change)
            } else if (try? container.decode(Skipped.self)) == nil {
                return
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(list)
    }

    /// Reads past any JSON value.
    private struct Skipped: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

extension ExpenseChangeValue {
    static func text(_ text: String) -> ExpenseChangeValue {
        ExpenseChangeValue(text: text)
    }

    static func money(_ money: Money) -> ExpenseChangeValue {
        ExpenseChangeValue(minorUnits: money.minorUnits, currencyCode: money.currencyCode)
    }

    static func date(_ date: Date) -> ExpenseChangeValue {
        ExpenseChangeValue(date: date.formatted(.iso8601))
    }

    static func payers(_ payers: [PersonID: Money], currencyCode: String) -> ExpenseChangeValue {
        let people = payers.keys.sorted()
        return ExpenseChangeValue(
            currencyCode: currencyCode,
            people: people.map(\.rawValue),
            amounts: Dictionary(uniqueKeysWithValues: payers.map { ($0.key.rawValue.uuidString, $0.value.minorUnits) })
        )
    }

    static func split(_ split: SplitDefinition) -> ExpenseChangeValue {
        ExpenseChangeValue(text: split.kindName, people: split.participants.sorted().map(\.rawValue))
    }

    static func group(_ id: GroupID) -> ExpenseChangeValue {
        ExpenseChangeValue(id: id.rawValue)
    }

    /// Something is there, such as a receipt, without saying what.
    static let present = ExpenseChangeValue()
}

extension SplitDefinition {
    /// The kind of split in words that never change, for storing in an edit.
    var kindName: String {
        switch self {
        case .equal: "equal"
        case .exact: "exact"
        case .percentages: "percentages"
        case .shares: "shares"
        case .adjustments: "adjustments"
        case .itemized: "itemized"
        }
    }
}

extension ActivityEntry {
    /// What an expense edit changed, when a version that records it made the edit. Otherwise empty.
    var editChanges: [ExpenseChange] {
        guard case .expenseEdited(let reference) = event else { return [] }
        return reference.changes?.list ?? []
    }
}
