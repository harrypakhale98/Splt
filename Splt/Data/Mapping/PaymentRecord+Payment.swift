import Foundation
import SpltCore

extension Payment {
    init(_ record: PaymentRecord) {
        self.init(
            id: PaymentID(rawValue: record.id),
            groupID: record.groupID.map { GroupID(rawValue: $0) },
            payer: PersonID(rawValue: record.payerID),
            receiver: PersonID(rawValue: record.receiverID),
            amount: Money(minorUnits: record.amountMinorUnits, currencyCode: record.currencyCode),
            date: record.date,
            note: record.note,
            deletedAt: record.deletedAt
        )
    }
}

extension PaymentRecord {
    convenience init(_ payment: Payment, createdAt: Date = Date()) {
        self.init(
            id: payment.id.rawValue,
            groupID: payment.groupID?.rawValue,
            payerID: payment.payer.rawValue,
            receiverID: payment.receiver.rawValue,
            amountMinorUnits: payment.amount.minorUnits,
            currencyCode: payment.amount.currencyCode,
            date: payment.date,
            note: payment.note,
            createdAt: createdAt
        )
        deletedAt = payment.deletedAt
    }

    func update(from payment: Payment) {
        groupID = payment.groupID?.rawValue
        zoneName = groupID?.uuidString
        payerID = payment.payer.rawValue
        receiverID = payment.receiver.rawValue
        amountMinorUnits = payment.amount.minorUnits
        currencyCode = payment.amount.currencyCode
        date = payment.date
        note = payment.note
    }
}
