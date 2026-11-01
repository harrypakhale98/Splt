extension SplitCalculator {
    static let fullBasisPoints: Int64 = 10_000

    static func percentageShares(basisPoints: [PersonID: Int64], total: Money) throws -> [PersonID: Int64] {
        guard !basisPoints.isEmpty else { throw SplitError.noParticipants }
        var sum: Int128 = 0
        for person in basisPoints.keys.sorted() {
            let value = basisPoints[person]!
            guard value >= 0 else { throw SplitError.negativePercentage(person) }
            sum += Int128(value)
        }
        guard sum == Int128(fullBasisPoints) else {
            throw SplitError.percentagesDoNotSumToHundred(actualBasisPoints: Int64(clamping: sum))
        }
        return try allocate(total.minorUnits, weights: basisPoints)
    }
}
