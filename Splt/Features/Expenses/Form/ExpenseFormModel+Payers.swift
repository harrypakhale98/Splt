import Foundation
import SpltCore

extension ExpenseFormModel {
    // MARK: Who's in

    /// Tapping a person chip: includes or removes them, or assigns the selected receipt item.
    func tapPerson(_ id: PersonID) {
        if let item = selectedItemID, split.method == .itemized {
            assign(id, to: item)
        } else {
            toggleParticipant(id)
        }
    }

    func selectEveryone() {
        participants = Set(members.map(\.id))
    }

    func isPayer(_ id: PersonID) -> Bool {
        payer.isMultiple ? payer.selected.contains(id) : payer.single == id
    }

    /// Long press "Paid by": this person alone paid.
    func makeSolePayer(_ id: PersonID) {
        payer = PayerState()
        payer.single = id
        payersFollowAmount = false
    }

    /// Long press "Also paid": adds or removes a second payer, dividing the payments evenly.
    func toggleAlsoPaid(_ id: PersonID) {
        if !payer.isMultiple {
            guard payer.single != id else { return }
            let first = payer.single ?? me?.id
            payer.isMultiple = true
            payer.selected = Set([first, id].compactMap { $0 })
        } else if payer.selected.contains(id) {
            payer.selected.remove(id)
        } else {
            payer.selected.insert(id)
        }
        if payer.selected.count <= 1 {
            let remaining = payer.selected.first ?? payer.single
            payer = PayerState()
            payer.single = remaining
            payersFollowAmount = false
        } else {
            payersFollowAmount = true
            splitPaymentsEvenly()
        }
    }

    /// Keeps evenly divided payments in step with the amount as it is typed.
    func refollowPayments() {
        guard payersFollowAmount, payer.isMultiple else { return }
        splitPaymentsEvenly()
    }

    /// "You paid 60.00, split 3 ways": the line above the Save button.
    var summaryLine: String {
        guard let total, !total.isZero else { return String(localized: "Enter an amount to get started.") }
        let amount = MoneyFormatting.magnitudeString(total, locale: locale)
        let who: String
        if payer.isMultiple {
            who = String(localized: "\(payer.selected.count) people paid \(amount)")
        } else if let single = payer.single {
            who = single == me?.id ? String(localized: "You paid \(amount)") : String(localized: "\(displayName(for: single)) paid \(amount)")
        } else {
            who = amount
        }
        let people = barPeople.count
        let how: String
        switch split.method {
        case .equal: how = String(localized: "split \(people) ways")
        case .percentage: how = String(localized: "split by percent")
        case .exact: how = String(localized: "split by amount")
        case .shares: how = String(localized: "split by shares")
        case .adjustment: how = String(localized: "split with adjustments")
        case .itemized: how = String(localized: "split by item")
        }
        return "\(who), \(how)"
    }
}
