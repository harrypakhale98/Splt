import Foundation
import SpltCore
import SwiftData

@MainActor
final class SwiftDataPaymentRepository: PaymentRepository {
    private let env: RepositoryContext

    init(_ env: RepositoryContext) {
        self.env = env
    }

    func payments(in group: GroupID, includeDeleted: Bool) throws -> [Payment] {
        try env.payments(inGroup: group, includeDeleted: includeDeleted)
    }

    func payment(id: PaymentID) throws -> Payment? {
        try env.paymentRecord(id).map(Payment.init)
    }

    func record(_ payment: Payment) throws {
        try insert(payment)
        try env.save()
    }

    @discardableResult
    func settle(_ debt: Debt, in group: GroupID, date: Date, note: String) throws -> Payment {
        let payment = Payment(settling: debt, groupID: group, date: date, note: note)
        try record(payment)
        return payment
    }

    @discardableResult
    func settleUp(group: GroupID, date: Date) throws -> [Payment] {
        guard let record = try env.groupRecord(group) else { throw DataError.notFound("group \(group)") }
        let ledger = try env.ledger(forGroup: group)
        let debts = record.simplifiesDebts ? ledger.simplifiedDebts : ledger.debts
        let payments = debts.map { Payment(settling: $0, groupID: group, date: date) }
        for payment in payments {
            try insert(payment)
        }
        try env.save()
        return payments
    }

    func undo(id: PaymentID) throws {
        guard let record = try env.paymentRecord(id) else { throw DataError.notFound("payment \(id)") }
        guard record.deletedAt == nil else { return }
        env.tracker.softDelete(record)
        try env.log(.paymentUndone(Self.reference(Payment(record))), groupID: Payment(record).groupID)
        try env.save()
    }

    func restore(id: PaymentID) throws {
        guard let record = try env.paymentRecord(id) else { throw DataError.notFound("payment \(id)") }
        guard record.deletedAt != nil else { return }
        env.tracker.restore(record)
        try env.log(.paymentRecorded(Self.reference(Payment(record))), groupID: Payment(record).groupID)
        try env.save()
    }

    /// Stores a payment without saving. Importers pass `logsActivity: false`.
    func insert(_ payment: Payment, logsActivity: Bool = true) throws {
        guard let groupID = payment.groupID else { throw DataError.missingGroup }
        guard try env.groupRecord(groupID) != nil else { throw DataError.notFound("group \(groupID)") }
        do {
            try payment.validate()
        } catch let error as PaymentError {
            throw DataError.invalidPayment(error)
        }
        guard try env.paymentRecord(payment.id) == nil else { throw DataError.alreadyExists("payment \(payment.id)") }
        let record = PaymentRecord(payment, createdAt: env.now())
        env.context.insert(record)
        env.tracker.recordEdit(record)
        if logsActivity {
            try env.log(.paymentRecorded(Self.reference(payment)), groupID: groupID)
        }
    }

    private static func reference(_ payment: Payment) -> PaymentReference {
        PaymentReference(id: payment.id, payer: payment.payer, receiver: payment.receiver, amount: payment.amount)
    }
}
