import Foundation
import SpltCore

@MainActor
protocol RecurringExpenseRepository {
    func templates(in group: GroupID) throws -> [RecurringExpense]
    func add(_ template: RecurringExpense) throws
    func update(_ template: RecurringExpense) throws
    func delete(id: UUID) throws
    /// Makes an expense for every occurrence that is due by `now` and was not made yet.
    ///
    /// Expense ids come from the template and the occurrence date, so two devices that both
    /// make the same occurrence produce one expense after sync, not two.
    @discardableResult func createDueExpenses(through now: Date) throws -> [Expense]
}
