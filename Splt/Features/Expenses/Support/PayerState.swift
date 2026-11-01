import Foundation
import SpltCore

/// Who paid: one person for the whole amount, or several people with an amount each.
struct PayerState: Equatable, Sendable {
    var isMultiple = false
    var single: PersonID?
    /// The people marked as having paid when several did.
    var selected: Set<PersonID> = []
    var amounts: [PersonID: String] = [:]

    enum Outcome: Equatable {
        case payers([PersonID: Money])
        case issue(ExpenseFormIssue)
    }

    func payers(total: Money, locale: Locale = .current) -> Outcome {
        guard isMultiple else {
            guard let single else { return .issue(.noPayer) }
            return .payers([single: total])
        }
        guard !selected.isEmpty else { return .issue(.noPayer) }
        var result: [PersonID: Money] = [:]
        for person in selected {
            let text = amounts[person, default: ""]
            if AmountInput.isBlank(text) { continue }
            guard let money = AmountInput.money(text, currencyCode: total.currencyCode, locale: locale, allowNegative: total.isNegative) else {
                return .issue(.invalidNumber)
            }
            if !money.isZero { result[person] = money }
        }
        guard let paid = try? Money.sum(result.values, currencyCode: total.currencyCode) else { return .issue(.invalidNumber) }
        let difference = total.minorUnits - paid.minorUnits
        if difference > 0 { return .issue(.payersShort(Money(minorUnits: difference, currencyCode: total.currencyCode))) }
        if difference < 0 { return .issue(.payersOver(Money(minorUnits: -difference, currencyCode: total.currencyCode))) }
        guard !result.isEmpty else { return .issue(.noPayer) }
        return .payers(result)
    }

    /// How much of the total the typed payments leave open. Negative when they are too high.
    func remaining(total: Money, locale: Locale = .current) -> Money? {
        guard isMultiple else { return nil }
        var paid: Int64 = 0
        for person in selected {
            let text = amounts[person, default: ""]
            if AmountInput.isBlank(text) { continue }
            guard let money = AmountInput.money(text, currencyCode: total.currencyCode, locale: locale, allowNegative: total.isNegative) else {
                return nil
            }
            paid += money.minorUnits
        }
        return Money(minorUnits: total.minorUnits - paid, currencyCode: total.currencyCode)
    }

    /// Divides the total evenly between the selected payers, ties broken by person id.
    mutating func splitEvenly(total: Money, locale: Locale = .current) {
        let people = selected.sorted()
        guard !people.isEmpty,
              let shares = try? LargestRemainderAllocator.allocate(
                total: total.minorUnits, weights: Dictionary(uniqueKeysWithValues: people.map { ($0, Int64(1)) })
              ) else { return }
        for person in people {
            amounts[person] = AmountInput.text(for: Money(minorUnits: shares[person] ?? 0, currencyCode: total.currencyCode), locale: locale)
        }
    }

    init() {}

    init(payers: [PersonID: Money], locale: Locale = .current) {
        if payers.count == 1, let only = payers.keys.first {
            single = only
        } else {
            isMultiple = true
            selected = Set(payers.keys)
            amounts = payers.mapValues { AmountInput.text(for: $0, locale: locale) }
            single = payers.keys.sorted().first
        }
    }
}
