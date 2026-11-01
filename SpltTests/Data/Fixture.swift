import Foundation
import SpltCore
import Testing
@testable import Splt

/// A signed-in user, two friends and one group holding all three, on an in-memory store.
@MainActor
struct Fixture {
    let services: DataServices
    let clock: TestClock
    let me: Person
    let sam: Person
    let priya: Person
    let group: SplitGroup

    init(simplifies: Bool = true) throws {
        clock = TestClock()
        services = try DataServices.inMemory(now: clock.reading)
        me = try services.people.ensureMe(name: "Me")
        sam = Person(name: "Sam", avatarSeed: 1)
        priya = Person(name: "Priya", avatarSeed: 2)
        try services.people.add(sam)
        try services.people.add(priya)
        group = SplitGroup(
            name: "Flat", currencyCode: "USD", memberIDs: [me.id, sam.id, priya.id], simplifiesDebts: simplifies
        )
        try services.groups.create(group)
    }

    var everyone: Set<PersonID> { [me.id, sam.id, priya.id] }

    func expense(
        _ title: String = "Dinner", cents: Int64 = 3000, paidBy payer: Person? = nil,
        splitBetween people: Set<PersonID>? = nil, date: Date? = nil
    ) -> Expense {
        Expense(
            groupID: group.id, title: title, total: usd(cents), date: date ?? clock.start,
            paidBy: (payer ?? me).id, split: .equal(participants: people ?? everyone)
        )
    }

    @discardableResult
    func addExpense(
        _ title: String = "Dinner", cents: Int64 = 3000, paidBy payer: Person? = nil,
        splitBetween people: Set<PersonID>? = nil, date: Date? = nil
    ) throws -> Expense {
        let value = expense(title, cents: cents, paidBy: payer, splitBetween: people, date: date)
        try services.expenses.add(value)
        return value
    }
}
