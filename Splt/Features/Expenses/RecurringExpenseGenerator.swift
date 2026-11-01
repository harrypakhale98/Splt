import SpltCore
import SwiftUI

/// Makes the expenses that recurring templates owe by now. Safe to run any number of times:
/// every occurrence has a fixed expense id, so a second run, or another device, adds nothing.
@MainActor
enum RecurringExpenseGenerator {
    @discardableResult
    static func run(services: DataServices, now: Date = Date()) -> [Expense] {
        (try? services.recurring.createDueExpenses(through: now)) ?? []
    }
}

private struct GeneratesRecurringExpenses: ViewModifier {
    @Environment(\.dataServices) private var services
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.task(id: phase) {
            guard phase == .active, let services else { return }
            RecurringExpenseGenerator.run(services: services)
        }
    }
}

extension View {
    /// Adds due recurring expenses whenever the app becomes active.
    func generatesRecurringExpenses() -> some View {
        modifier(GeneratesRecurringExpenses())
    }
}
