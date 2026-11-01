import Foundation
import SpltCore
@testable import Splt

enum GroupsTestCalendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let english = Locale(identifier: "en_US")
}

/// A noon UTC moment on the given day.
func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    GroupsTestCalendar.utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

extension Fixture {
    /// An expense in this fixture's group with a category and a payer, for filter and total tests.
    func add(
        _ title: String, cents: Int64, on date: Date, category: ExpenseCategory = .general,
        paidBy payer: Person? = nil, in other: SplitGroup? = nil
    ) throws -> Expense {
        let target = other ?? group
        let expense = Expense(
            groupID: target.id, title: title, total: usdAmount(cents), date: date, category: category,
            paidBy: (payer ?? me).id, split: .equal(participants: Set(target.memberIDs))
        )
        try services.expenses.add(expense)
        return expense
    }
}

/// A left-groups record that lives only for one test.
func isolatedLeftGroups() -> LeftGroupsStore {
    LeftGroupsStore(defaults: UserDefaults(suiteName: "splt.tests.\(UUID().uuidString)")!)
}
