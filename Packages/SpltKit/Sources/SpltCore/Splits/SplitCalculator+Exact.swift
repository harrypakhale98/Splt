extension SplitCalculator {
    static func exactShares(amounts: [PersonID: Money], total: Money) throws -> [PersonID: Int64] {
        guard !amounts.isEmpty else { throw SplitError.noParticipants }
        let direction = sign(of: total)
        var sum: Int128 = 0
        var units: [PersonID: Int64] = [:]
        for person in amounts.keys.sorted() {
            let amount = amounts[person]!
            try requireCurrency(of: amount, matches: total)
            guard !pointsWrongWay(amount.minorUnits, direction: direction) else {
                throw SplitError.negativeShare(person)
            }
            sum += Int128(amount.minorUnits)
            units[person] = amount.minorUnits
        }
        guard sum == Int128(total.minorUnits) else {
            throw SplitError.exactAmountsDoNotMatchTotal(
                expected: total,
                actual: Money(minorUnits: Int64(clamping: sum), currencyCode: total.currencyCode)
            )
        }
        return units
    }
}
