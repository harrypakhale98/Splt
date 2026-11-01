/// Turns a split definition and a total into what each person owes.
///
/// Shares always add up exactly to the total. Spare minor units are handed out by the
/// largest-remainder method with ties broken by sorted person id, so every device computes
/// the same answer. Negative totals (refunds) produce negative shares that mirror the
/// positive case.
public enum SplitCalculator {
    /// Calculates shares, plus a per person breakdown for itemized splits.
    public static func calculate(_ split: SplitDefinition, total: Money) throws -> ShareResult {
        let units: [PersonID: Int64]
        switch split {
        case .equal(let participants):
            units = try equalShares(participants: participants, total: total)
        case .exact(let amounts):
            units = try exactShares(amounts: amounts, total: total)
        case .percentages(let basisPoints):
            units = try percentageShares(basisPoints: basisPoints, total: total)
        case .shares(let weights):
            units = try weightedShares(weights: weights, total: total)
        case .adjustments(let participants, let adjustments):
            units = try adjustedShares(participants: participants, adjustments: adjustments, total: total)
        case .itemized(let itemized):
            return try itemizedResult(itemized, total: total)
        }
        return ShareResult(total: total, shares: money(units, like: total))
    }

    /// Shorthand for `calculate(_:total:).shares`.
    public static func shares(for split: SplitDefinition, total: Money) throws -> [PersonID: Money] {
        try calculate(split, total: total).shares
    }

    static func money(_ units: [PersonID: Int64], like total: Money) -> [PersonID: Money] {
        units.mapValues { Money(minorUnits: $0, currencyCode: total.currencyCode) }
    }

    static func requireCurrency(of amount: Money, matches total: Money) throws {
        guard amount.currencyCode == total.currencyCode else {
            throw SplitError.currencyMismatch(expected: total.currencyCode, found: amount.currencyCode)
        }
    }

    static func allocate(_ amount: Int64, weights: [PersonID: Int64], tieBreakOffset: Int = 0) throws -> [PersonID: Int64] {
        do {
            return try LargestRemainderAllocator.allocate(total: amount, weights: weights, tieBreakOffset: tieBreakOffset)
        } catch AllocationError.noWeights {
            throw SplitError.noParticipants
        } catch AllocationError.zeroTotalWeight {
            throw SplitError.zeroTotalWeight
        } catch AllocationError.overflow {
            throw SplitError.overflow
        } catch let error as AllocationError {
            throw SplitError.allocationFailed(error)
        }
    }

    static func int64(_ value: Int128) throws -> Int64 {
        guard let result = Int64(exactly: value) else { throw SplitError.overflow }
        return result
    }

    /// 1 for normal expenses, -1 for refunds. Zero totals count as normal.
    static func sign(of total: Money) -> Int64 {
        total.minorUnits < 0 ? -1 : 1
    }

    /// Whether a share points the wrong way for the expense: negative on a purchase, positive on a refund.
    static func pointsWrongWay(_ units: Int64, direction: Int64) -> Bool {
        direction > 0 ? units < 0 : units > 0
    }
}
