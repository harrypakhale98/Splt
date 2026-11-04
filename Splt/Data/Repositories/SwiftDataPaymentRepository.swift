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

    func recordAll(_ payments: [Payment]) throws {
        guard !payments.isEmpty else { return }
        do {
            let me = try env.currentUser()?.personID
            try insertBatch(payments)
            let counts = Dictionary(grouping: payments.compactMap(\.groupID), by: { $0 }).mapValues(\.count)
            for group in counts.keys.sorted() {
                try env.log(.expensesImported(expenses: 0, payments: counts[group] ?? 0), groupID: group, actor: me)
            }
            try env.save()
        } catch {
            env.tracker.rollback()
            throw error
        }
    }

    /// Stores many payments without saving or logging, after checking them all with a few queries.
    func insertBatch(_ payments: [Payment]) throws {
        let payments = payments.map(Self.fitted)
        var knownGroups = Set<GroupID>()
        var seen = Set<PaymentID>()
        for payment in payments {
            guard let groupID = payment.groupID else { throw DataError.missingGroup }
            if knownGroups.insert(groupID).inserted, try env.groupRecord(groupID) == nil {
                throw DataError.notFound("group \(groupID)")
            }
            do {
                try payment.validate()
            } catch let error as PaymentError {
                throw DataError.invalidPayment(error)
            }
            guard seen.insert(payment.id).inserted else { throw DataError.alreadyExists("payment \(payment.id)") }
        }
        let existing = try env.existingPaymentIDs(among: payments.map(\.id.rawValue))
        if let clash = payments.first(where: { existing.contains($0.id.rawValue) }) {
            throw DataError.alreadyExists("payment \(clash.id)")
        }
        let created = env.now()
        for payment in payments {
            let record = PaymentRecord(payment, createdAt: created)
            env.context.insert(record)
            env.tracker.recordEdit(record)
        }
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
        let payment = Self.fitted(payment)
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

    private static func fitted(_ payment: Payment) -> Payment {
        var payment = payment
        payment.note = payment.note.limited(to: RecordLimits.text)
        return payment
    }

    private static func reference(_ payment: Payment) -> PaymentReference {
        PaymentReference(id: payment.id, payer: payment.payer, receiver: payment.receiver, amount: payment.amount)
    }
}
