import Foundation
import SpltCore
@testable import Splt

/// A busy store for performance checks: many groups, many people and thousands of expenses.
/// Lives in the test target, so it never ships.
@MainActor
struct LargeStoreFixture {
    let services: DataServices
    let me: Person
    let groups: [SplitGroup]
    let expenseCount: Int

    init(groupCount: Int = 30, expenseCount: Int = 5000, peopleCount: Int = 40) throws {
        let clock = TestClock()
        services = try DataServices.inMemory(now: clock.reading)
        me = try services.people.ensureMe(name: "Me")
        let friends = (1...peopleCount).map { Person(name: "Friend \($0)", avatarSeed: $0) }
        for friend in friends { try services.people.add(friend) }

        var made: [SplitGroup] = []
        for index in 0..<groupCount {
            let pool = (0..<11).map { friends[(index * 3 + $0) % friends.count] }
            let group = SplitGroup(
                name: "Group \(index + 1)", currencyCode: index.isMultiple(of: 7) ? "EUR" : "USD",
                memberIDs: [me.id] + pool.map(\.id)
            )
            try services.groups.create(group)
            made.append(group)
        }
        groups = made
        self.expenseCount = expenseCount

        // the first group is the biggest, so one screen carries thousands of rows. Records go in directly
        // and are saved once, so building the store takes seconds instead of minutes
        let context = services.container.mainContext
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for number in 0..<expenseCount {
            let group = number % 3 == 0 ? made[0] : made[next(made.count)]
            let members = group.memberIDs
            let payer = members[next(members.count)]
            let sharing = Set(members.filter { _ in next(3) != 0 }.prefix(8)).union([payer])
            let total = Int64(100 + next(50_000))
            let expense = Expense(
                groupID: group.id, title: "Expense \(number)", total: Money(minorUnits: total, currencyCode: group.currencyCode),
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(number) * 3_600),
                category: ExpenseCategory.allCases[next(ExpenseCategory.allCases.count)],
                paidBy: payer, split: .equal(participants: sharing)
            )
            context.insert(ExpenseRecord(expense, extras: ExpenseExtras(), createdBy: me.id, createdAt: expense.date))
        }
        try context.save()
        services.groupsStore.refresh()
        services.friendsStore.refresh()
    }
}
