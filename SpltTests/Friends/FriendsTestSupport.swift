import Foundation
import SpltCore
@testable import Splt

/// A throwaway preferences store for one test.
func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "splt.tests.friends.\(UUID().uuidString)")!
}

func summary(_ name: String, _ amounts: [Money] = []) -> FriendSummary {
    FriendSummary(person: Person(name: name), balance: amounts, byGroup: [])
}
