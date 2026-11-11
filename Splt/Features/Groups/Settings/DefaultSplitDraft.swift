import Foundation
import SpltCore

/// What the Default Split screen is editing, in the same terms as the expense form's editors:
/// ticked people for an equal split, typed percentages, and share counts.
struct DefaultSplitDraft: Equatable {
    var method: DefaultSplit.Method
    /// The group's members, in display order.
    private(set) var members: [PersonID]
    /// Who an equal split includes.
    var included: Set<PersonID>
    /// Typed percentages, as the expense form keeps them. A blank field is 0.
    var percent: [PersonID: String]
    /// Hundredths of a share, so 100 is one share.
    var shares: [PersonID: Int64]

    init(split: DefaultSplit?, members: [PersonID], locale: Locale = .current) {
        self.members = members
        method = split?.method ?? .equal
        included = Set(members)
        percent = [:]
        shares = [:]
        guard let split else { return }
        let weight = { (person: PersonID) in split.weights[person] ?? split.method.newcomerWeight }
        switch split.method {
        case .equal:
            included = Set(members.filter { weight($0) > 0 })
        case .percentages:
            for person in members {
                let value = weight(person)
                percent[person] = value > 0 ? AmountInput.hundredthsText(value, locale: locale) : ""
            }
        case .shares:
            for person in members { shares[person] = max(weight(person), 0) }
        }
    }

    /// Follows a change of members: someone new gets the method's newcomer weight, someone gone is dropped.
    mutating func setMembers(_ ids: [PersonID]) {
        let added = ids.filter { !members.contains($0) }
        members = ids
        let present = Set(ids)
        included = included.intersection(present).union(added)
        percent = percent.filter { present.contains($0.key) }
        shares = shares.filter { present.contains($0.key) }
    }

    func shareCount(for person: PersonID) -> Double {
        Double(shares[person] ?? 100) / 100
    }

    mutating func setShareCount(_ value: Double, for person: PersonID) {
        shares[person] = Int64((max(value, 0) * 100).rounded())
    }

    /// The percentage typed for each member in hundredths, or nil while a field is not a number.
    func basisPoints(locale: Locale = .current) -> [PersonID: Int64]? {
        var values: [PersonID: Int64] = [:]
        for person in members {
            let text = percent[person, default: ""]
            if AmountInput.isBlank(text) { values[person] = 0; continue }
            guard let value = AmountInput.basisPoints(text, locale: locale) else { return nil }
            values[person] = value
        }
        return values
    }

    /// What is left to reach 100%, in hundredths of a percent. Fields that are not numbers count as 0.
    func percentRemaining(locale: Locale = .current) -> Int64 {
        let typed = members.compactMap { AmountInput.basisPoints(percent[$0, default: ""], locale: locale) }
        return 10_000 - typed.reduce(0, +)
    }

    mutating func fillPercentagesEvenly(locale: Locale = .current) {
        let people = members.sorted()
        guard !people.isEmpty,
              let parts = try? LargestRemainderAllocator.allocate(
                total: 10_000, weights: Dictionary(uniqueKeysWithValues: people.map { ($0, Int64(1)) })
              ) else { return }
        for person in people {
            percent[person] = AmountInput.hundredthsText(parts[person] ?? 0, locale: locale)
        }
    }

    /// The weight of each member under the current method, for the strip. Nil while percentages don't parse.
    func weights(locale: Locale = .current) -> [PersonID: Int64]? {
        switch method {
        case .equal:
            Dictionary(uniqueKeysWithValues: members.map { ($0, included.contains($0) ? 1 : 0) })
        case .percentages:
            basisPoints(locale: locale)
        case .shares:
            Dictionary(uniqueKeysWithValues: members.map { ($0, shares[$0] ?? 100) })
        }
    }

    /// True when a new expense could start with it: someone is in, and percentages add up to 100.
    func isValid(locale: Locale = .current) -> Bool {
        guard let weights = weights(locale: locale), weights.values.contains(where: { $0 > 0 }) else { return false }
        return method != .percentages || weights.values.reduce(0, +) == 10_000
    }

    /// The split to store. Nil for an equal split between everyone, which is what a group does without one.
    func split(locale: Locale = .current) -> DefaultSplit? {
        guard let weights = weights(locale: locale) else { return nil }
        let split = DefaultSplit(method: method, weights: weights)
        return split.isPlainEqual(for: members) ? nil : split
    }
}
