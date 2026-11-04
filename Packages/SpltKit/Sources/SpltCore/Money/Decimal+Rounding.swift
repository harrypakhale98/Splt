import Foundation

extension Decimal {
    /// The nearest whole number below or equal to the value.
    var flooredToWhole: Decimal { roundedToWhole(.down) }

    /// The nearest whole number, with halves rounded away from zero.
    var roundedHalfAwayFromZero: Decimal { roundedToWhole(.plain) }

    /// The value as a 64 bit integer, or nil if it is fractional or out of range.
    var exactInt64: Int64? {
        guard !isNaN, self == flooredToWhole else { return nil }
        let number = NSDecimalNumber(decimal: self)
        guard abs(self) < Decimal(Int64.max) else { return nil }
        return number.int64Value
    }

    private func roundedToWhole(_ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, mode)
        return result
    }
}
