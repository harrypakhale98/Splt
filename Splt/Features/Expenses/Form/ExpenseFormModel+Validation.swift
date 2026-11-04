import Foundation
import SpltCore

extension ExpenseFormModel {
    /// The first thing keeping Save off, or nil when the expense can be saved.
    var issue: ExpenseFormIssue? {
        guard let total else { return AmountInput.isBlank(amountText) ? .missingAmount : .invalidAmount }
        guard !total.isZero else { return .missingAmount }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingTitle }
        if case .issue(let issue) = payer.payers(total: total, locale: locale) { return issue }
        return splitIssue
    }

    var canSave: Bool { issue == nil && group != nil }

    var blockingReason: String? { issue?.message(locale: locale) }

    var splitIssue: ExpenseFormIssue? {
        guard let total, !total.isZero else { return nil }
        switch splitResult(total: total) {
        case .success: return nil
        case .failure(let issue): return issue
        }
    }

    /// What the payers still owe against the total. Negative when over. Nil unless several people paid.
    var payerRemaining: Money? {
        guard let total else { return nil }
        return payer.remaining(total: total, locale: locale)
    }

    /// What is left to assign in the active split: money for exact and itemized, nil for other methods.
    var splitRemaining: Money? {
        guard let total, !total.isZero else { return nil }
        switch split.method {
        case .exact:
            let typed = participantList.compactMap { AmountInput.money(split.exact[$0.id, default: ""], currencyCode: currencyCode, locale: locale) }
            return Money(minorUnits: total.minorUnits - typed.reduce(0) { $0 + $1.minorUnits }, currencyCode: currencyCode)
        case .itemized:
            guard let items = split.itemizedTotal(currencyCode: currencyCode, locale: locale) else { return nil }
            return Money(minorUnits: total.minorUnits - items.minorUnits, currencyCode: currencyCode)
        default:
            return nil
        }
    }

    /// Percentage points left to assign, in hundredths. Nil unless splitting by percentage.
    var percentRemaining: Int64? {
        guard split.method == .percentage else { return nil }
        let typed = participantList.compactMap { AmountInput.basisPoints(split.percent[$0.id, default: ""], locale: locale) }
        return 10_000 - typed.reduce(0, +)
    }

    /// The people in the split with what each owes, for the live preview.
    var sharePreview: [(person: Person, amount: Money)] {
        guard let total, !total.isZero, case .success(let result) = splitResult(total: total) else { return [] }
        return members.compactMap { person in
            result.shares[person.id].map { (person, $0) }
        }
    }

    func splitResult(total: Money) -> Result<ShareResult, ExpenseFormIssue> {
        let outcome = split.definition(participants: participants, currencyCode: total.currencyCode, locale: locale)
        guard case .definition(let definition) = outcome else {
            if case .issue(let issue) = outcome { return .failure(issue) }
            return .failure(.invalidSplit)
        }
        do {
            return .success(try SplitCalculator.calculate(definition, total: total))
        } catch let error as SplitError {
            return .failure(mapped(error))
        } catch {
            return .failure(.invalidSplit)
        }
    }

    private func mapped(_ error: SplitError) -> ExpenseFormIssue {
        switch error {
        case .noParticipants: .noParticipants
        case .exactAmountsDoNotMatchTotal(let expected, let actual):
            difference(expected: expected, actual: actual)
        case .itemizedTotalMismatch(let itemsAndCharges, let total):
            difference(expected: total, actual: itemsAndCharges)
        case .percentagesDoNotSumToHundred(let actual):
            actual < 10_000 ? .percentShort(basisPoints: 10_000 - actual) : .percentOver(basisPoints: actual - 10_000)
        case .negativePercentage, .negativeWeight, .negativeAmount: .negativeValue
        case .zeroTotalWeight: .noShares
        case .negativeShare(let id): .negativeShare(name: displayName(for: id))
        case .itemWithoutAssignees(let index):
            .itemWithoutPeople(name: split.items.indices.contains(index) ? itemName(split.items[index]) : "")
        default: .invalidSplit
        }
    }

    private func difference(expected: Money, actual: Money) -> ExpenseFormIssue {
        let gap = expected.minorUnits - actual.minorUnits
        let amount = Money(minorUnits: abs(gap), currencyCode: expected.currencyCode)
        return gap > 0 ? .splitShort(amount) : .splitOver(amount)
    }

    func itemName(_ item: ItemDraft) -> String {
        let trimmed = item.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "this item") : trimmed
    }
}
