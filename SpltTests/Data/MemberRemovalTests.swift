import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Removing a member with recurring expenses")
struct MemberRemovalTests {
    @Test func aMemberOnARecurringExpenseCannotBeRemoved() throws {
        let fixture = try Fixture()
        let rent = RecurringExpense(
            groupID: fixture.group.id, title: "Rent", total: usdAmount(900), payers: [fixture.me.id: usdAmount(900)],
            split: .equal(participants: [fixture.me.id, fixture.sam.id]),
            rule: RecurrenceRule(frequency: .monthly, startDate: fixture.clock.start)
        )
        try fixture.services.recurring.add(rent)
        #expect(throws: (any Error).self) { try fixture.services.groups.removeMember(fixture.sam.id, from: fixture.group.id) }
        try fixture.services.groups.removeMember(fixture.priya.id, from: fixture.group.id)

        var withoutSam = rent
        withoutSam.split = .equal(participants: [fixture.me.id])
        try fixture.services.recurring.update(withoutSam)
        try fixture.services.groups.removeMember(fixture.sam.id, from: fixture.group.id)
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.memberIDs.contains(fixture.sam.id) == false)
    }

    @Test func aFinishedRecurringExpenseDoesNotBlockRemoval() throws {
        let fixture = try Fixture()
        let start = fixture.clock.start
        try fixture.services.recurring.add(RecurringExpense(
            groupID: fixture.group.id, title: "Rent", total: usdAmount(900), payers: [fixture.me.id: usdAmount(900)],
            split: .equal(participants: [fixture.me.id, fixture.sam.id]),
            rule: RecurrenceRule(frequency: .monthly, startDate: start, endDate: start),
            lastCreatedOccurrence: start
        ))
        try fixture.services.groups.removeMember(fixture.sam.id, from: fixture.group.id)
    }

    @Test func aPausedRecurringExpenseStillBlocksRemoval() throws {
        let fixture = try Fixture()
        try fixture.services.recurring.add(RecurringExpense(
            groupID: fixture.group.id, title: "Rent", total: usdAmount(900), payers: [fixture.sam.id: usdAmount(900)],
            split: .equal(participants: [fixture.me.id]),
            rule: RecurrenceRule(frequency: .monthly, startDate: fixture.clock.start), isActive: false
        ))
        #expect(throws: DataError.memberOnRecurringExpense("Rent")) {
            try fixture.services.groups.removeMember(fixture.sam.id, from: fixture.group.id)
        }
    }
}
