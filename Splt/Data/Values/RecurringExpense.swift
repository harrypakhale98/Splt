import Foundation
import SpltCore

/// A template that makes a new expense on a schedule.
struct RecurringExpense: Hashable, Sendable, Identifiable {
    var id: UUID
    var groupID: GroupID?
    var title: String
    var total: Money
    var category: ExpenseCategory
    var payers: [PersonID: Money]
    var split: SplitDefinition
    var note: String
    var rule: RecurrenceRule
    /// The date of the latest occurrence that already became an expense, or the moment the template
    /// was resumed: later occurrences are the only ones it still makes.
    var lastCreatedOccurrence: Date?
    var isActive: Bool
    var createdBy: PersonID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        groupID: GroupID? = nil,
        title: String,
        total: Money,
        category: ExpenseCategory = .general,
        payers: [PersonID: Money],
        split: SplitDefinition,
        note: String = "",
        rule: RecurrenceRule,
        lastCreatedOccurrence: Date? = nil,
        isActive: Bool = true,
        createdBy: PersonID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.total = total
        self.category = category
        self.payers = payers
        self.split = split
        self.note = note
        self.rule = rule
        self.lastCreatedOccurrence = lastCreatedOccurrence
        self.isActive = isActive
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    /// Whether a future occurrence would charge or credit this person. A paused template counts,
    /// because it can be resumed. One whose schedule has ended does not.
    func willInvolve(_ person: PersonID) -> Bool {
        guard payers.keys.contains(person) || split.participants.contains(person) else { return false }
        return rule.nextOccurrence(after: lastCreatedOccurrence ?? .distantPast) != nil
    }

    /// The expense this template makes for one occurrence.
    func expense(on occurrence: Date) -> Expense {
        Expense(
            groupID: groupID, title: title, total: total, date: occurrence, category: category,
            payers: payers, split: split, note: note
        )
    }
}
