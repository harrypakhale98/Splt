extension SplitCalculator {
    /// Gives each person their items, then spreads tax, tip and discount in proportion to those items.
    static func itemizedResult(_ itemized: ItemizedSplit, total: Money) throws -> ShareResult {
        guard !itemized.items.isEmpty else { throw SplitError.noParticipants }
        guard total.minorUnits >= 0 else { throw SplitError.negativeAmount }
        let tax = try extra(itemized.tax, total: total)
        let tip = try extra(itemized.tip, total: total)
        let discount = try extra(itemized.discount, total: total)

        var itemTotals: [PersonID: Int64] = [:]
        var subtotal: Int128 = 0
        for (index, item) in itemized.items.enumerated() {
            try requireCurrency(of: item.amount, matches: total)
            guard item.amount.minorUnits >= 0 else { throw SplitError.negativeAmount }
            guard !item.assignees.isEmpty else { throw SplitError.itemWithoutAssignees(itemIndex: index) }
            subtotal += Int128(item.amount.minorUnits)
            let parts = try allocate(
                item.amount.minorUnits,
                weights: Dictionary(uniqueKeysWithValues: item.assignees.map { ($0, 1) }),
                tieBreakOffset: index
            )
            for (person, units) in parts {
                let (sum, overflow) = itemTotals[person, default: 0].addingReportingOverflow(units)
                guard !overflow else { throw SplitError.overflow }
                itemTotals[person] = sum
            }
        }

        guard Int128(discount) <= subtotal else { throw SplitError.discountExceedsSubtotal }
        let expected = subtotal + Int128(tax) + Int128(tip) - Int128(discount)
        guard expected == Int128(total.minorUnits) else {
            throw SplitError.itemizedTotalMismatch(
                expected: Money(minorUnits: Int64(clamping: expected), currencyCode: total.currencyCode),
                actual: total
            )
        }

        let weights = subtotal > 0 ? itemTotals : itemTotals.mapValues { _ in 1 }
        let taxParts = try allocate(tax, weights: weights)
        let tipParts = try allocate(tip, weights: weights)
        let discountParts = try allocate(discount, weights: weights)

        var shares: [PersonID: Money] = [:]
        var breakdown: [PersonID: ShareBreakdown] = [:]
        for person in itemTotals.keys.sorted() {
            let itemUnits = itemTotals[person] ?? 0
            let personTax = taxParts[person] ?? 0
            let personTip = tipParts[person] ?? 0
            let personDiscount = discountParts[person] ?? 0
            let personTotal = try int64(Int128(itemUnits) + Int128(personTax) + Int128(personTip) - Int128(personDiscount))
            let make = { (units: Int64) in Money(minorUnits: units, currencyCode: total.currencyCode) }
            shares[person] = make(personTotal)
            breakdown[person] = ShareBreakdown(
                items: make(itemUnits),
                tax: make(personTax),
                tip: make(personTip),
                discount: make(personDiscount),
                total: make(personTotal)
            )
        }
        return ShareResult(total: total, shares: shares, breakdown: breakdown)
    }

    private static func extra(_ money: Money?, total: Money) throws -> Int64 {
        guard let money else { return 0 }
        try requireCurrency(of: money, matches: total)
        guard money.minorUnits >= 0 else { throw SplitError.negativeAmount }
        return money.minorUnits
    }
}
