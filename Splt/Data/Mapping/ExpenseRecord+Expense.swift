import Foundation
import SpltCore

extension Expense {
    /// Reads an expense from its record. Throws `DataError.corruptRecord` if a stored blob cannot be decoded.
    init(_ record: ExpenseRecord) throws {
        let payers: [PersonID: Money]
        let split: SplitDefinition
        do {
            payers = try RecordCoding.decode([PersonID: Money].self, from: record.payersData)
            split = try RecordCoding.decode(SplitDefinition.self, from: record.splitData)
        } catch {
            throw DataError.corruptRecord("expense \(record.recordName)")
        }
        self.init(
            id: ExpenseID(rawValue: record.id),
            groupID: record.groupID.map { GroupID(rawValue: $0) },
            title: record.title,
            total: Money(minorUnits: record.totalMinorUnits, currencyCode: record.currencyCode),
            date: record.date,
            category: ExpenseCategory(rawValue: record.categoryRaw) ?? .other,
            payers: payers,
            split: split,
            note: record.note,
            deletedAt: record.deletedAt
        )
    }
}

extension ExpenseRecord {
    convenience init(_ expense: Expense, extras: ExpenseExtras = ExpenseExtras(), createdBy: PersonID? = nil, createdAt: Date = Date()) {
        self.init(
            id: expense.id.rawValue,
            groupID: expense.groupID?.rawValue,
            title: expense.title,
            totalMinorUnits: expense.total.minorUnits,
            currencyCode: expense.total.currencyCode,
            date: expense.date,
            categoryRaw: expense.category.rawValue,
            payersData: RecordCoding.encode(expense.payers),
            splitData: RecordCoding.encode(expense.split),
            note: expense.note,
            createdAt: createdAt
        )
        deletedAt = expense.deletedAt
        createdByID = createdBy?.rawValue
        apply(extras)
    }

    /// Copies the core fields. The tombstone is not touched: deleting goes through the repository.
    func update(from expense: Expense) {
        groupID = expense.groupID?.rawValue
        zoneName = groupID?.uuidString
        title = expense.title
        totalMinorUnits = expense.total.minorUnits
        currencyCode = expense.total.currencyCode
        date = expense.date
        categoryRaw = expense.category.rawValue
        payersData = RecordCoding.encode(expense.payers)
        splitData = RecordCoding.encode(expense.split)
        note = expense.note
    }

    var extras: ExpenseExtras {
        ExpenseExtras(
            receiptFileName: receiptFileName,
            location: latitude.flatMap { latitude in
                longitude.map { ExpenseLocation(name: locationName, latitude: latitude, longitude: $0) }
            },
            recurrence: recurrenceData.flatMap { try? RecordCoding.decode(RecurrenceRule.self, from: $0) },
            recurringExpenseID: recurringExpenseID
        )
    }

    func apply(_ extras: ExpenseExtras) {
        receiptFileName = extras.receiptFileName
        locationName = extras.location?.name
        latitude = extras.location?.latitude
        longitude = extras.location?.longitude
        recurrenceData = extras.recurrence.map { RecordCoding.encode($0) }
        recurringExpenseID = extras.recurringExpenseID
    }

    var history: [ExpenseEditEntry] {
        get { (try? RecordCoding.decode([ExpenseEditEntry].self, from: editHistoryData)) ?? [] }
        set { editHistoryData = RecordCoding.encode(newValue) }
    }

    var details: ExpenseDetails {
        ExpenseDetails(
            extras: extras, history: history, createdAt: createdAt,
            createdBy: createdByID.map { PersonID(rawValue: $0) }, modifiedAt: modifiedAt
        )
    }
}
