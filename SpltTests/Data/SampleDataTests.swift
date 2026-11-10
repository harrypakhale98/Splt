#if DEBUG
import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Sample data")
struct SampleDataTests {
    private func load() throws -> (DataServices, SampleData.Trip) {
        let services = try DataServices.inMemory(now: SampleClock().tick)
        return (services, try SampleData.populate(into: services))
    }

    @Test func buildsATripWithFiveFriends() throws {
        let (services, trip) = try load()
        #expect(trip.friends.count == 5)
        let group = try #require(try services.groups.group(id: trip.trip.id))
        #expect(group.memberIDs.count == 6)
        #expect(group.kind == .trip)
        #expect(group.currencyCode == "USD")
        #expect(try services.people.friends().count == 5)
        #expect(try services.groups.groups(includeArchived: true).count == 3)
    }

    @Test func coversEverySplitStrategyAndARefund() throws {
        let (services, trip) = try load()
        let expenses = try services.expenses.expenses(in: trip.trip.id)
        func has(_ test: (SplitDefinition) -> Bool) -> Bool { expenses.contains { test($0.split) } }
        #expect(has { if case .equal = $0 { true } else { false } })
        #expect(has { if case .exact = $0 { true } else { false } })
        #expect(has { if case .percentages = $0 { true } else { false } })
        #expect(has { if case .shares = $0 { true } else { false } })
        #expect(has { if case .adjustments = $0 { true } else { false } })
        #expect(has { if case .itemized = $0 { true } else { false } })
        #expect(expenses.contains { $0.isRefund })
        #expect(expenses.contains { $0.payers.count > 1 })
    }

    @Test func everyExpenseIsValidAndTheLedgerIsClean() throws {
        let (services, trip) = try load()
        for group in [trip.trip, trip.flat, trip.friendGroup] {
            for expense in try services.expenses.expenses(in: group.id) {
                try expense.validate()
            }
            let balances = try services.groups.balances(for: group.id)
            #expect(balances.ledger.issues.isEmpty)
            for table in balances.netBalances.values {
                #expect(table.values.map(\.minorUnits).reduce(0, +) == 0)
            }
        }
    }

    @Test func includesASoftDeletedExpenseAndASettlement() throws {
        let (services, trip) = try load()
        let all = try services.expenses.expenses(in: trip.trip.id, includeDeleted: true)
        #expect(all.filter(\.isDeleted).count == 1)
        #expect(try services.payments.payments(in: trip.trip.id).count == 1)
    }

    @Test func friendsAndGroupsHaveBalances() throws {
        let (services, _) = try load()
        services.friendsStore.refresh()
        services.groupsStore.refresh()
        #expect(!services.friendsStore.totals.isSettled)
        #expect(services.groupsStore.summaries.contains { !$0.isSettled })
        #expect(services.friendsStore.summaries.count == 5)
        #expect(try services.people.friendBalances().contains { $0.byGroup.count == 2 })
    }

    @Test func hasCommentsAndAnActivityTrail() throws {
        let (services, trip) = try load()
        let expense = try #require(trip.expenses["airbnb"])
        let comment = try #require(try services.comments.comments(on: expense).first)
        #expect(comment.reactions.count == 1)
        #expect(try services.activity.entries(in: trip.trip.id, limit: 100).count > 10)
    }

    @Test func identifiersAreStableBetweenRuns() throws {
        let (_, first) = try load()
        let (_, second) = try load()
        #expect(first.trip.id == second.trip.id)
        #expect(first.maya.id == second.maya.id)
        #expect(first.expenses == second.expenses)
    }

    @Test func previewServicesComeLoaded() {
        let services = SampleData.previewServices()
        #expect(!services.groupsStore.summaries.isEmpty)
        #expect(services.friendsStore.summaries.count == 5)
    }
}
#endif
