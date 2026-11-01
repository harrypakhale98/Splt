import Foundation
import Observation
import SpltCore
import SwiftData

@MainActor
@Observable
final class RecurringExpensesModel {
    let groupID: GroupID
    @ObservationIgnored let services: DataServices
    @ObservationIgnored private var observer: ContainerChangeObserver?

    private(set) var group: SplitGroup?
    private(set) var templates: [RecurringExpense] = []
    private(set) var people: [PersonID: Person] = [:]
    private(set) var me: Person?
    private(set) var actionError: String?

    init(groupID: GroupID, services: DataServices) {
        self.groupID = groupID
        self.services = services
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.reload() }
        reload()
    }

    func reload() {
        do {
            group = try services.groups.group(id: groupID)
            templates = try services.recurring.templates(in: groupID)
            me = try services.people.me()
            let ids = Set(templates.flatMap { $0.payers.keys }).sorted()
            people = Dictionary(try services.people.people(ids: ids).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            templates = []
        }
    }

    /// The next date the template will make an expense, or nil once its schedule has ended.
    func nextDate(for template: RecurringExpense) -> Date? {
        guard let last = template.lastCreatedOccurrence else { return template.rule.occurrence(at: 0) }
        return template.rule.nextOccurrence(after: last)
    }

    func payerSummary(for template: RecurringExpense) -> String {
        ExpenseSummary.payerText(template.payers, currentPerson: me?.id, names: people.mapValues(\.name))
    }

    func setActive(_ active: Bool, for template: RecurringExpense) {
        var updated = template
        updated.isActive = active
        perform { try services.recurring.update(updated) }
    }

    func delete(_ template: RecurringExpense) {
        perform { try services.recurring.delete(id: template.id) }
    }

    func dismissError() { actionError = nil }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            reload()
        } catch {
            actionError = String(localized: "That did not work. Try again.")
        }
    }
}
