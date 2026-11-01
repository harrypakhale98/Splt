import Foundation

/// A shared cost: who paid, and how it is divided.
///
/// A negative total is a refund. Payers then hold negative amounts (they received money
/// back) and every share is negative, so the ledger gives the money back to the people
/// who bore the original cost. Deleted expenses stay in history with `deletedAt` set and
/// are ignored by the ledger.
public struct Expense: Hashable, Sendable, Codable, Identifiable {
    public var id: ExpenseID
    public var groupID: GroupID?
    public var title: String
    public var total: Money
    public var date: Date
    public var category: ExpenseCategory
    /// What each payer put in. Must add up to `total`.
    public var payers: [PersonID: Money]
    public var split: SplitDefinition
    public var note: String
    public var deletedAt: Date?

    public init(
        id: ExpenseID = ExpenseID(),
        groupID: GroupID? = nil,
        title: String,
        total: Money,
        date: Date,
        category: ExpenseCategory = .general,
        payers: [PersonID: Money],
        split: SplitDefinition,
        note: String = "",
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.total = total
        self.date = date
        self.category = category
        self.payers = payers
        self.split = split
        self.note = note
        self.deletedAt = deletedAt
    }

    /// An expense paid in full by one person.
    public init(
        id: ExpenseID = ExpenseID(),
        groupID: GroupID? = nil,
        title: String,
        total: Money,
        date: Date,
        category: ExpenseCategory = .general,
        paidBy payer: PersonID,
        split: SplitDefinition,
        note: String = "",
        deletedAt: Date? = nil
    ) {
        self.init(
            id: id, groupID: groupID, title: title, total: total, date: date, category: category,
            payers: [payer: total], split: split, note: note, deletedAt: deletedAt
        )
    }

    /// True when the total is negative: money coming back rather than being spent.
    public var isRefund: Bool { total.isNegative }

    public var isDeleted: Bool { deletedAt != nil }

    /// Everyone who paid or owes something.
    public var participants: Set<PersonID> {
        Set(payers.keys).union(split.participants)
    }

    /// What each person owes for this expense.
    public func shares() throws -> ShareResult {
        do {
            return try SplitCalculator.calculate(split, total: total)
        } catch let error as SplitError {
            throw ExpenseError.invalidSplit(error)
        }
    }

    /// Checks payers and split. Throws an `ExpenseError` describing the first problem found.
    public func validate() throws {
        _ = try netBalances()
    }

    /// Paid minus owed for each person. Positive means they are owed money, negative means they owe.
    /// The values add up to zero.
    public func netBalances() throws -> [PersonID: Money] {
        guard !payers.isEmpty else { throw ExpenseError.noPayers }
        let direction: Int64 = total.isNegative ? -1 : 1
        var paidSum: Int128 = 0
        var net: [PersonID: Int128] = [:]
        for payer in payers.keys.sorted() {
            let amount = payers[payer]!
            guard amount.currencyCode == total.currencyCode else {
                throw ExpenseError.currencyMismatch(expected: total.currencyCode, found: amount.currencyCode)
            }
            let wrongWay = direction > 0 ? amount.minorUnits < 0 : amount.minorUnits > 0
            guard !wrongWay else { throw ExpenseError.payerAmountPointsWrongWay(payer) }
            paidSum += Int128(amount.minorUnits)
            net[payer] = Int128(amount.minorUnits)
        }
        guard paidSum == Int128(total.minorUnits) else {
            throw ExpenseError.payersDoNotMatchTotal(
                expected: total,
                actual: Money(minorUnits: Int64(clamping: paidSum), currencyCode: total.currencyCode)
            )
        }

        for (person, share) in try shares().shares {
            net[person, default: 0] -= Int128(share.minorUnits)
        }
        var result: [PersonID: Money] = [:]
        for (person, value) in net {
            guard let units = Int64(exactly: value) else { throw ExpenseError.overflow }
            result[person] = Money(minorUnits: units, currencyCode: total.currencyCode)
        }
        return result
    }
}
