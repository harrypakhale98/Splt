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
    @State private var catchUp = RecurringCatchUp()

    func body(content: Content) -> some View {
        content
            .task(id: phase) {
                guard phase == .active, let services else { return }
                RecurringExpenseGenerator.run(services: services)
            }
            .task(id: services.map(ObjectIdentifier.init)) {
                catchUp.follow(services)
            }
    }
}

/// Catches up between app launches too: after a save, such as a new template that started last month, a group
/// brought back from the archive or a template synced from another phone, and at midnight with the app open.
/// A run that finds nothing due saves nothing, so following saves never loops.
@MainActor
private final class RecurringCatchUp {
    private var observer: ContainerChangeObserver?
    private var dayChange: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?

    func follow(_ services: DataServices?) {
        observer = nil
        if let dayChange { NotificationCenter.default.removeObserver(dayChange) }
        dayChange = nil
        guard let services else { return }
        observer = ContainerChangeObserver(
            container: services.container, watching: [RecurringExpenseRecord.self, GroupRecord.self]
        ) { [weak self, weak services] in
            guard let services else { return }
            self?.schedule(services)
        }
        dayChange = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) {
            [weak self, weak services] _ in
            MainActor.assumeIsolated {
                guard let services else { return }
                self?.schedule(services)
            }
        }
    }

    /// Waits a moment, so a burst of saves runs it once.
    private func schedule(_ services: DataServices) {
        pending?.cancel()
        pending = Task { [weak services] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let services else { return }
            RecurringExpenseGenerator.run(services: services)
        }
    }
}

extension View {
    /// Adds due recurring expenses whenever the app becomes active, after saves and at midnight.
    func generatesRecurringExpenses() -> some View {
        modifier(GeneratesRecurringExpenses())
    }
}
