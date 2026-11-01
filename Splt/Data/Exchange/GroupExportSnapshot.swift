import Foundation
import SpltCore

/// Everything an export needs, gathered once so the exporters stay pure.
struct GroupExportSnapshot: Sendable {
    var group: SplitGroup
    /// Current members first, then anyone who only appears in old expenses.
    var people: [Person]
    var expenses: [Expense]
    var payments: [Payment]
    var exportedAt: Date
}
