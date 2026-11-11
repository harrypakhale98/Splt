import Foundation
import SpltCore

extension ExpenseFormModel {
    /// Starts a new expense with the group's default split. Without one, or when nothing in it still
    /// works for today's members, the form keeps its equal split between everyone. A bill already
    /// split by item keeps its items.
    func applyDefaultSplit(of group: SplitGroup) {
        guard split.method != .itemized,
              let resolved = group.defaultSplit?.resolved(for: members.map(\.id)) else { return }
        participants = Set(resolved.participants)
        switch resolved.method {
        case .equal:
            split.method = .equal
        case .percentages:
            split.method = .percentage
            split.percent = resolved.weights.mapValues { AmountInput.hundredthsText($0, locale: locale) }
        case .shares:
            split.method = .shares
            split.weights = resolved.weights.mapValues { AmountInput.hundredthsText($0, locale: locale) }
        }
    }
}
