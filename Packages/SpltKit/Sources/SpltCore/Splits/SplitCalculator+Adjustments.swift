extension SplitCalculator {
    /// Each person's own adjustment, plus an equal part of whatever the adjustments leave over.
    static func adjustedShares(
        participants: Set<PersonID>,
        adjustments: [PersonID: Money],
        total: Money
    ) throws -> [PersonID: Int64] {
        guard !participants.isEmpty else { throw SplitError.noParticipants }
        var adjustmentSum: Int128 = 0
        for person in adjustments.keys.sorted() {
            guard participants.contains(person) else { throw SplitError.adjustmentForNonParticipant(person) }
            let amount = adjustments[person]!
            try requireCurrency(of: amount, matches: total)
            adjustmentSum += Int128(amount.minorUnits)
        }

        let remainder = try int64(Int128(total.minorUnits) - adjustmentSum)
        let equalParts = try allocate(remainder, weights: Dictionary(uniqueKeysWithValues: participants.map { ($0, 1) }))
        let direction = sign(of: total)
        var units: [PersonID: Int64] = [:]
        for person in participants.sorted() {
            let adjustment = Int128(adjustments[person]?.minorUnits ?? 0)
            let share = try int64(adjustment + Int128(equalParts[person] ?? 0))
            guard !pointsWrongWay(share, direction: direction) else { throw SplitError.negativeShare(person) }
            units[person] = share
        }
        return units
    }
}
