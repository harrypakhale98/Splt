import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Add expense launcher")
struct AddExpenseLauncherTests {
    private let trip = SplitGroup(name: "Trip", currencyCode: "USD")
    private let flat = SplitGroup(name: "Flat", currencyCode: "USD")
    private let direct = SplitGroup(name: "Sam", currencyCode: "USD", kind: .friend)

    private func left(_ ids: GroupID...) -> LeftGroupsStore {
        let store = LeftGroupsStore(defaults: UserDefaults(suiteName: "splt.tests.launcher.\(UUID().uuidString)")!)
        ids.forEach(store.insert)
        return store
    }

    @Test func startsInTheGroupUsedLast() {
        let id = AddExpenseLauncher.startingGroup(among: [trip, flat], lastUsed: flat.id.description, left: left())
        #expect(id == flat.id)
    }

    @Test func aFriendsDirectGroupUsedLastFallsBackToTheNewestGroup() {
        let id = AddExpenseLauncher.startingGroup(among: [direct, trip, flat], lastUsed: direct.id.description, left: left())
        #expect(id == trip.id)
    }

    @Test func onlyDirectGroupsMeansNoGroup() {
        #expect(AddExpenseLauncher.startingGroup(among: [direct], lastUsed: "", left: left()) == nil)
    }

    @Test func aGroupYouLeftIsSkipped() {
        let id = AddExpenseLauncher.startingGroup(among: [trip, flat], lastUsed: trip.id.description, left: left(trip.id))
        #expect(id == flat.id)
    }
}
