extension SplitCalculator {
    static func weightedShares(weights: [PersonID: Int64], total: Money) throws -> [PersonID: Int64] {
        guard !weights.isEmpty else { throw SplitError.noParticipants }
        for person in weights.keys.sorted() where weights[person]! < 0 {
            throw SplitError.negativeWeight(person)
        }
        return try allocate(total.minorUnits, weights: weights)
    }
}
