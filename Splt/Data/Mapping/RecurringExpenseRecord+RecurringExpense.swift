import Foundation
import SpltCore

extension RecurringExpense {
    init(_ record: RecurringExpenseRecord) throws {
        let payers: [PersonID: Money]
        let split: SplitDefinition
        let rule: RecurrenceRule
        do {
            payers = try RecordCoding.decode([PersonID: Money].self, from: record.payersData)
            split = try RecordCoding.decode(SplitDefinition.self, from: record.splitData)
            rule = try RecordCoding.decode(RecurrenceRule.self, from: record.ruleData)
        } catch {
            throw DataError.corruptRecord("recurring expense \(record.recordName)")
        }
        self.init(
            id: record.id,
            groupID: record.groupID.map { GroupID(rawValue: $0) },
            title: record.title,
            total: Money(minorUnits: record.totalMinorUnits, currencyCode: record.currencyCode),
            category: ExpenseCategory(rawValue: record.categoryRaw) ?? .other,
            payers: payers,
            split: split,
            note: record.note,
            rule: rule,
            lastCreatedOccurrence: record.lastCreatedOccurrence,
            isActive: record.isActive,
            createdBy: record.createdByID.map { PersonID(rawValue: $0) },
            createdAt: record.createdAt
        )
    }
}

extension RecurringExpenseRecord {
    convenience init(_ template: RecurringExpense) {
        self.init(
            id: template.id,
            groupID: template.groupID?.rawValue,
            title: template.title,
            totalMinorUnits: template.total.minorUnits,
            currencyCode: template.total.currencyCode,
            categoryRaw: template.category.rawValue,
            payersData: RecordCoding.encode(template.payers),
            splitData: RecordCoding.encode(template.split),
            note: template.note,
            ruleData: RecordCoding.encode(template.rule),
            isActive: template.isActive,
            createdAt: template.createdAt
        )
        lastCreatedOccurrence = template.lastCreatedOccurrence
        createdByID = template.createdBy?.rawValue
    }

    func update(from template: RecurringExpense) {
        groupID = template.groupID?.rawValue
        zoneName = groupID?.uuidString
        title = template.title
        totalMinorUnits = template.total.minorUnits
        currencyCode = template.total.currencyCode
        categoryRaw = template.category.rawValue
        payersData = RecordCoding.encode(template.payers)
        splitData = RecordCoding.encode(template.split)
        note = template.note
        ruleData = RecordCoding.encode(template.rule)
        lastCreatedOccurrence = template.lastCreatedOccurrence
        isActive = template.isActive
    }
}
