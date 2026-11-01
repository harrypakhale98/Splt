import Foundation
import SpltCore
import Testing
@testable import Splt

/// Builds form models on the shared in-memory fixture, with parsers that never touch the system model.
@MainActor
struct ExpenseFormHarness {
    let fixture: Fixture
    let receipts: ReceiptStore
    let defaults: UserDefaults

    init() throws {
        fixture = try Fixture()
        let folder = FileManager.default.temporaryDirectory.appending(path: "splt-receipts-\(UUID().uuidString)")
        receipts = ReceiptStore(directory: folder)
        defaults = UserDefaults(suiteName: "splt-tests-\(UUID().uuidString)") ?? .standard
    }

    var dependencies: ExpenseFormModel.Dependencies {
        var value = ExpenseFormModel.Dependencies()
        value.parser = RuleBasedQuickAddParser()
        value.categories = KeywordCategorySuggester()
        value.receipts = receipts
        value.locale = Locale(identifier: "en_US")
        value.defaults = defaults
        let start = fixture.clock.start
        value.now = { start }
        return value
    }

    func newExpense(prefill: ExpenseDraft? = nil) -> ExpenseFormModel {
        ExpenseFormModel(
            mode: .add(groupID: fixture.group.id, prefill: prefill), services: fixture.services, dependencies: dependencies
        )
    }

    func editor(for id: ExpenseID) -> ExpenseFormModel {
        ExpenseFormModel(mode: .edit(id), services: fixture.services, dependencies: dependencies)
    }

    /// A form that already holds a valid 60 dollar dinner split three ways.
    func filledDinner() -> ExpenseFormModel {
        let model = newExpense()
        model.amountText = "60"
        model.title = "Dinner"
        return model
    }

    var me: PersonID { fixture.me.id }
    var sam: PersonID { fixture.sam.id }
    var priya: PersonID { fixture.priya.id }
}
