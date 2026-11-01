import Foundation
import SpltCore

@MainActor
protocol PaymentRepository {
    /// Newest first.
    func payments(in group: GroupID, includeDeleted: Bool) throws -> [Payment]
    func payment(id: PaymentID) throws -> Payment?
    /// Validates and stores a settlement, and writes an activity entry.
    func record(_ payment: Payment) throws
    /// Records a payment that settles a suggested debt.
    @discardableResult func settle(_ debt: Debt, in group: GroupID, date: Date, note: String) throws -> Payment
    /// Records a payment for every suggested settlement, which leaves the group square.
    @discardableResult func settleUp(group: GroupID, date: Date) throws -> [Payment]
    /// Undoes a settlement. The payment stays in history but no longer counts.
    func undo(id: PaymentID) throws
    /// Brings back a settlement that was undone.
    func restore(id: PaymentID) throws
}

extension PaymentRepository {
    func payments(in group: GroupID) throws -> [Payment] {
        try payments(in: group, includeDeleted: false)
    }

    @discardableResult
    func settle(_ debt: Debt, in group: GroupID, date: Date) throws -> Payment {
        try settle(debt, in: group, date: date, note: "")
    }
}
