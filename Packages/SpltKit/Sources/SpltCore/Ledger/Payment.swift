import Foundation

/// A settlement: `payer` handed `amount` to `receiver` outside the app, or recorded it in the app.
public struct Payment: Hashable, Sendable, Codable, Identifiable {
    public var id: PaymentID
    public var groupID: GroupID?
    public var payer: PersonID
    public var receiver: PersonID
    public var amount: Money
    public var date: Date
    public var note: String
    public var deletedAt: Date?

    public init(
        id: PaymentID = PaymentID(),
        groupID: GroupID? = nil,
        payer: PersonID,
        receiver: PersonID,
        amount: Money,
        date: Date,
        note: String = "",
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.payer = payer
        self.receiver = receiver
        self.amount = amount
        self.date = date
        self.note = note
        self.deletedAt = deletedAt
    }

    /// A payment that settles a suggested debt.
    public init(settling debt: Debt, groupID: GroupID? = nil, date: Date, note: String = "") {
        self.init(
            groupID: groupID, payer: debt.debtor, receiver: debt.creditor,
            amount: debt.amount, date: date, note: note
        )
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// Throws a `PaymentError` unless the payment is between two people for a positive amount.
    public func validate() throws {
        guard payer != receiver else { throw PaymentError.samePerson }
        guard amount.isPositive else { throw PaymentError.nonPositiveAmount }
    }
}
