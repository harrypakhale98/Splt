extension Money {
    /// A zero amount in the given currency.
    public static func zero(currencyCode: String) -> Money {
        Money(minorUnits: 0, currencyCode: currencyCode)
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isPositive: Bool { minorUnits > 0 }
    public var isNegative: Bool { minorUnits < 0 }

    /// Whether both amounts use the same currency.
    public func isSameCurrency(as other: Money) -> Bool {
        currencyCode == other.currencyCode
    }

    /// Throws `MoneyError.currencyMismatch` unless both amounts share a currency.
    public func requireSameCurrency(as other: Money) throws {
        guard isSameCurrency(as: other) else {
            throw MoneyError.currencyMismatch(currencyCode, other.currencyCode)
        }
    }

    /// The sum of two amounts of the same currency.
    public func adding(_ other: Money) throws -> Money {
        try requireSameCurrency(as: other)
        let (value, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: value, currencyCode: currencyCode)
    }

    /// The difference of two amounts of the same currency.
    public func subtracting(_ other: Money) throws -> Money {
        try requireSameCurrency(as: other)
        let (value, overflow) = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: value, currencyCode: currencyCode)
    }

    /// The amount with its sign flipped.
    public func negated() throws -> Money {
        let (value, overflow) = Int64(0).subtractingReportingOverflow(minorUnits)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: value, currencyCode: currencyCode)
    }

    /// The amount without its sign.
    public func absoluteValue() throws -> Money {
        isNegative ? try negated() : self
    }

    /// The amount times a whole number.
    public func multiplied(by factor: Int64) throws -> Money {
        let (value, overflow) = minorUnits.multipliedReportingOverflow(by: factor)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: value, currencyCode: currencyCode)
    }

    /// A share of the amount in basis points (1 basis point is 0.01 percent), rounded half away from zero.
    /// Handy for tips and tax: `bill.percentage(basisPoints: 1800)` is 18 percent.
    public func percentage(basisPoints: Int64) throws -> Money {
        let product = Int128(minorUnits) * Int128(basisPoints)
        var quotient = product / 10_000
        let remainder = product % 10_000
        if remainder.magnitude * 2 >= 10_000 {
            quotient += product < 0 ? -1 : 1
        }
        guard let value = Int64(exactly: quotient) else { throw MoneyError.overflow }
        return Money(minorUnits: value, currencyCode: currencyCode)
    }

    /// The sum of many amounts. The currency is explicit so an empty list still has a type.
    public static func sum<S: Sequence>(_ values: S, currencyCode: String) throws -> Money where S.Element == Money {
        var total = Money.zero(currencyCode: currencyCode)
        for value in values {
            total = try total.adding(value)
        }
        return total
    }
}
