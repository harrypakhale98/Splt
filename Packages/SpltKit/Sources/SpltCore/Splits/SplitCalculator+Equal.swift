extension SplitCalculator {
    static func equalShares(participants: Set<PersonID>, total: Money) throws -> [PersonID: Int64] {
        guard !participants.isEmpty else { throw SplitError.noParticipants }
        return try allocate(total.minorUnits, weights: Dictionary(uniqueKeysWithValues: participants.map { ($0, 1) }))
    }
}
