import Foundation
import SpltCore

extension ExpenseFormModel {
    /// How many shares a person has, as a number for the stepper.
    func shareCount(for id: PersonID) -> Double {
        let text = split.weights[id, default: "1"]
        guard let hundredths = AmountInput.hundredths(text, locale: locale) else { return 0 }
        return Double(hundredths) / 100
    }

    func setShareCount(_ value: Double, for id: PersonID) {
        let hundredths = Int64((max(value, 0) * 100).rounded())
        split.weights[id] = AmountInput.hundredthsText(hundredths, locale: locale)
    }

    /// Gives everyone in the split the same percentage, with the odd hundredth going to the first people.
    func fillPercentagesEvenly() {
        let people = participantList.map(\.id).sorted()
        guard !people.isEmpty,
              let parts = try? LargestRemainderAllocator.allocate(
                total: 10_000, weights: Dictionary(uniqueKeysWithValues: people.map { ($0, Int64(1)) })
              ) else { return }
        for person in people {
            split.percent[person] = AmountInput.hundredthsText(parts[person] ?? 0, locale: locale)
        }
    }
}

extension ExpenseFormModel {
    /// Changes whenever something the duplicate check depends on changes.
    var refreshKey: String {
        "\(amountText)|\(currencyCode)|\(title)|\(date.timeIntervalSince1970)"
    }
}
