import Foundation
import SpltCore

/// One line of an itemized bill while it is being edited.
struct ItemDraft: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var amountText = ""
    var assignees: Set<PersonID> = []
}

/// What the person typed into the split editors, one set of fields per method, so switching
/// methods back and forth never loses work. `definition` turns the active method into a
/// `SplitDefinition` for the calculator.
struct SplitEditorState: Equatable, Sendable {
    var method: SplitMethod = .equal
    var exact: [PersonID: String] = [:]
    var percent: [PersonID: String] = [:]
    var weights: [PersonID: String] = [:]
    var adjustments: [PersonID: String] = [:]
    var items: [ItemDraft] = []
    var taxText = ""
    var tipText = ""
    var discountText = ""

    enum Outcome: Equatable {
        case definition(SplitDefinition)
        case issue(ExpenseFormIssue)
    }

    func definition(participants: Set<PersonID>, currencyCode: String, locale: Locale = .current) -> Outcome {
        switch method {
        case .equal:
            return participants.isEmpty ? .issue(.noParticipants) : .definition(.equal(participants: participants))
        case .exact:
            return amounts(exact, for: participants, currencyCode: currencyCode, locale: locale, allowNegative: false)
                .map { .definition(.exact(amounts: $0)) } ?? .issue(participants.isEmpty ? .noParticipants : .invalidNumber)
        case .percentage:
            guard !participants.isEmpty else { return .issue(.noParticipants) }
            var values: [PersonID: Int64] = [:]
            for person in participants {
                let text = percent[person, default: ""]
                if AmountInput.isBlank(text) { values[person] = 0; continue }
                guard let value = AmountInput.basisPoints(text, locale: locale) else { return .issue(.invalidNumber) }
                values[person] = value
            }
            return .definition(.percentages(basisPoints: values))
        case .shares:
            guard !participants.isEmpty else { return .issue(.noParticipants) }
            var parsed: [PersonID: Int64] = [:]
            for person in participants {
                let text = weights[person, default: "1"]
                if AmountInput.isBlank(text) { parsed[person] = 0; continue }
                guard let value = AmountInput.hundredths(text, locale: locale) else { return .issue(.invalidNumber) }
                parsed[person] = value
            }
            // whole counts stay whole; a fraction such as 1.5 scales everyone by 100 to stay exact
            let scale: Int64 = parsed.values.allSatisfy { $0 % 100 == 0 } ? 100 : 1
            return .definition(.shares(weights: parsed.mapValues { $0 / scale }))
        case .adjustment:
            guard !participants.isEmpty else { return .issue(.noParticipants) }
            guard let signed = amounts(adjustments, for: participants, currencyCode: currencyCode, locale: locale, allowNegative: true) else {
                return .issue(.invalidNumber)
            }
            return .definition(.adjustments(participants: participants, adjustments: signed.filter { !$0.value.isZero }))
        case .itemized:
            return itemizedDefinition(currencyCode: currencyCode, locale: locale)
        }
    }

    /// Typed amounts for the people listed; a blank field counts as zero. Nil when a field is not a number.
    private func amounts(
        _ texts: [PersonID: String], for people: Set<PersonID>, currencyCode: String, locale: Locale, allowNegative: Bool
    ) -> [PersonID: Money]? {
        guard !people.isEmpty else { return nil }
        var result: [PersonID: Money] = [:]
        for person in people {
            let text = texts[person, default: ""]
            if AmountInput.isBlank(text) {
                result[person] = .zero(currencyCode: currencyCode)
            } else if let money = AmountInput.money(text, currencyCode: currencyCode, locale: locale, allowNegative: allowNegative) {
                result[person] = money
            } else {
                return nil
            }
        }
        return result
    }

    private func itemizedDefinition(currencyCode: String, locale: Locale) -> Outcome {
        guard !items.isEmpty else { return .issue(.noItems) }
        var split: [SplitItem] = []
        for item in items {
            guard let amount = AmountInput.money(item.amountText, currencyCode: currencyCode, locale: locale) else {
                return .issue(.invalidNumber)
            }
            split.append(SplitItem(id: item.id, name: item.name, amount: amount, assignees: item.assignees))
        }
        func optional(_ text: String) -> Money?? {
            if AmountInput.isBlank(text) { return .some(nil) }
            guard let money = AmountInput.money(text, currencyCode: currencyCode, locale: locale) else { return nil }
            return .some(money)
        }
        guard let tax = optional(taxText), let tip = optional(tipText), let discount = optional(discountText) else {
            return .issue(.invalidNumber)
        }
        return .definition(.itemized(ItemizedSplit(items: split, tax: tax, tip: tip, discount: discount)))
    }

    /// Money that is spread over the items: their sum plus tax and tip minus the discount, or nil if a field is invalid.
    func itemizedTotal(currencyCode: String, locale: Locale = .current) -> Money? {
        guard case .definition(.itemized(let itemized)) = itemizedDefinition(currencyCode: currencyCode, locale: locale) else {
            return nil
        }
        let zero = Money.zero(currencyCode: currencyCode)
        let parts = itemized.items.map(\.amount) + [itemized.tax ?? zero, itemized.tip ?? zero]
        guard let sum = try? Money.sum(parts, currencyCode: currencyCode) else { return nil }
        return try? sum.subtracting(itemized.discount ?? zero)
    }

    /// Fills the editors from an existing split, for editing.
    init(definition: SplitDefinition, locale: Locale = .current) {
        method = SplitMethod(definition)
        switch definition {
        case .equal:
            break
        case .exact(let amounts):
            exact = amounts.mapValues { AmountInput.text(for: $0, locale: locale) }
        case .percentages(let basisPoints):
            percent = basisPoints.mapValues { AmountInput.hundredthsText($0, locale: locale) }
        case .shares(let values):
            weights = values.mapValues { String($0) }
        case .adjustments(_, let values):
            adjustments = values.mapValues { AmountInput.text(for: $0, locale: locale) }
        case .itemized(let itemized):
            items = itemized.items.map {
                ItemDraft(id: $0.id, name: $0.name, amountText: AmountInput.text(for: $0.amount, locale: locale), assignees: $0.assignees)
            }
            taxText = itemized.tax.map { AmountInput.text(for: $0, locale: locale) } ?? ""
            tipText = itemized.tip.map { AmountInput.text(for: $0, locale: locale) } ?? ""
            discountText = itemized.discount.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        }
    }

    init() {}
}
