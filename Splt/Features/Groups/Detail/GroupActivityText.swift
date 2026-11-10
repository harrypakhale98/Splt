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
            // someone who adds themselves joined, as ChangeMessages says it too
            if id == entry.actorID { return String(localized: "\(actor) joined the group") }
            return String(localized: "\(actor) added \(member(id))")
        case .memberRemoved(let id):
            if id == entry.actorID { return String(localized: "\(actor) left the group") }
            return String(localized: "\(actor) removed \(member(id))")
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

    /// The person something was done to, which for the reader is "you" in the middle of a sentence.
    private func member(_ id: PersonID) -> String {
        id == currentPerson ? String(localized: "you") : name(id)
    }

    private func name(_ id: PersonID?) -> String {
        guard let id else { return String(localized: "Someone") }
        if id == currentPerson { return String(localized: "You") }
        return names[id] ?? String(localized: "Someone")
    }
}
