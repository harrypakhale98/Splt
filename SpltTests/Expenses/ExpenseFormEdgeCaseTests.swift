import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Expense form edge cases")
@MainActor
struct ExpenseFormEdgeCaseTests {
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    private func item(_ name: String, _ cents: Int64) -> ReceiptLineItem {
        ReceiptLineItem(name: name, quantity: 1, unitPrice: nil, total: usd(cents))
    }

    @Test func aNoteWithOnlyAShareKeepsItsCurrency() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.describeText = "Sam owes €20"
        await model.fillFromNote()
        #expect(model.currencyCode == "EUR")
        #expect(model.split.exact[harness.sam] == "20.00")
    }
}
