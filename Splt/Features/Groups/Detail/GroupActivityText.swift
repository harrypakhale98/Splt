import Foundation
import SpltCore

/// Turns an activity entry into a plain sentence.
struct GroupActivityText {
    var currentPerson: PersonID?
    var names: [PersonID: String]
    var locale: Locale = .current

    func sentence(for entry: ActivityEntry) -> String {
        let actor = name(entry.actorID)
        switch entry.event {
        case .groupCreated(let name):
            return String(localized: "\(actor) created \(name)")
        case .groupRenamed(let from, let to):
            return String(localized: "\(actor) renamed \(from) to \(to)")
        case .groupArchived:
            return String(localized: "\(actor) archived the group")
        case .groupRestored:
            return String(localized: "\(actor) restored the group")
        case .memberAdded(let id):
            let member = name(id)
            return String(localized: "\(actor) added \(member)")
        case .memberRemoved(let id):
            let member = name(id)
            return String(localized: "\(actor) removed \(member)")
        case .expenseAdded(let expense):
            return String(localized: "\(actor) added \(expense.title)")
        case .expenseEdited(let expense):
            return String(localized: "\(actor) edited \(expense.title)")
        case .expenseDeleted(let expense):
            return String(localized: "\(actor) deleted \(expense.title)")
        case .expenseRestored(let expense):
            return String(localized: "\(actor) restored \(expense.title)")
        case .paymentRecorded(let payment):
            let payer = name(payment.payer), receiver = name(payment.receiver)
            let amount = MoneyFormatting.magnitudeString(payment.amount, locale: locale)
            return String(localized: "\(payer) paid \(receiver) \(amount)")
        case .paymentUndone(let payment):
            let payer = name(payment.payer), receiver = name(payment.receiver)
            let amount = MoneyFormatting.magnitudeString(payment.amount, locale: locale)
            return String(localized: "\(actor) undid \(payer) paying \(receiver) \(amount)")
        case .commentAdded(let expense, let text):
            guard let expense else { return String(localized: "\(actor) commented: \(text)") }
            return String(localized: "\(actor) commented on \(expense.title): \(text)")
        case .expensesImported(let expenses, let payments):
            return String(localized: "\(actor) imported \(expenses) expenses and \(payments) payments")
        }
    }

    private func name(_ id: PersonID?) -> String {
        guard let id else { return String(localized: "Someone") }
        if id == currentPerson { return String(localized: "You") }
        return names[id] ?? String(localized: "Someone")
    }
}
