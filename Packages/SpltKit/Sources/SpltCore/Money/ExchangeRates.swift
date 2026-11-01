import Foundation

/// Exchange rates against a base currency, with optional hand pinned pairs.
///
/// `rates` holds how many units of each currency one unit of the base buys, the shape that
/// ECB backed feeds use. Pinned rates win over the table and work in both directions.
/// Rates are only used to convert; stored amounts stay integer minor units.
public struct ExchangeRates: Hashable, Sendable, Codable {
    public var baseCurrency: String
    public var rates: [String: Decimal]
    public var pinned: [PinnedRate]
    public var asOf: Date?

    public init(
        baseCurrency: String,
        rates: [String: Decimal],
        pinned: [PinnedRate] = [],
        asOf: Date? = nil
    ) {
        self.baseCurrency = baseCurrency.uppercased()
        self.rates = Dictionary(rates.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: { _, latest in latest })
        self.pinned = pinned
        self.asOf = asOf
    }

    /// Units of `to` for one unit of `from`, or nil when the pair is unknown.
    public func rate(from: String, to: String) -> Decimal? {
        let from = from.uppercased()
        let to = to.uppercased()
        if from == to { return 1 }
        if let direct = pinned.first(where: { $0.from == from && $0.to == to }), direct.rate > 0 {
            return direct.rate
        }
        if let reverse = pinned.first(where: { $0.from == to && $0.to == from }), reverse.rate > 0 {
            return 1 / reverse.rate
        }
        guard let fromRate = quote(for: from), let toRate = quote(for: to), fromRate > 0, toRate > 0 else {
            return nil
        }
        return toRate / fromRate
    }

    /// Converts one amount, rounding half away from zero.
    public func convert(_ money: Money, to currencyCode: String) throws -> Money {
        let target = currencyCode.uppercased()
        let exact = try exactMinorUnits(of: money, in: target)
        guard let value = exact.roundedHalfAwayFromZero.exactInt64 else { throw ExchangeRatesError.overflow }
        return Money(minorUnits: value, currencyCode: target)
    }

    /// Converts and adds up several amounts per key without losing or gaining a unit overall.
    ///
    /// Each key's amounts are converted exactly and summed, then the whole set is rounded
    /// with the largest-remainder method so the converted values add up to the rounded
    /// total of the exact values. Balances that sum to zero in each source currency still
    /// sum to zero in the target currency.
    public func convert<Key: Hashable & Comparable>(
        _ amounts: [Key: [Money]],
        to currencyCode: String
    ) throws -> [Key: Money] {
        let target = currencyCode.uppercased()
        let keys = amounts.keys.sorted()
        var exact: [Decimal] = []
        for key in keys {
            var sum = Decimal.zero
            for money in amounts[key] ?? [] {
                sum += try exactMinorUnits(of: money, in: target)
            }
            exact.append(sum)
        }

        let floors = exact.map(\.flooredToWhole)
        let fractions = zip(exact, floors).map { $0 - $1 }
        let totalExact = exact.reduce(Decimal.zero, +)
        let floorTotal = floors.reduce(Decimal.zero, +)
        guard let leftover = (totalExact.roundedHalfAwayFromZero - floorTotal).exactInt64 else {
            throw ExchangeRatesError.overflow
        }

        let order = keys.indices.sorted { lhs, rhs in
            fractions[lhs] != fractions[rhs] ? fractions[lhs] > fractions[rhs] : lhs < rhs
        }
        var values: [Int64] = []
        for floor in floors {
            guard let value = floor.exactInt64 else { throw ExchangeRatesError.overflow }
            values.append(value)
        }
        for index in order.prefix(Int(leftover)) {
            values[index] += 1
        }

        var result: [Key: Money] = [:]
        for (index, key) in keys.enumerated() {
            result[key] = Money(minorUnits: values[index], currencyCode: target)
        }
        return result
    }

    private func quote(for code: String) -> Decimal? {
        code == baseCurrency ? 1 : rates[code]
    }

    /// The amount in the target currency's minor units, not yet rounded.
    private func exactMinorUnits(of money: Money, in target: String) throws -> Decimal {
        guard let rate = rate(from: money.currencyCode, to: target) else {
            throw ExchangeRatesError.missingRate(from: money.currencyCode, to: target)
        }
        let shift = Currency.minorUnitExponent(for: target) - money.exponent
        return Decimal(money.minorUnits) * rate * Decimal(sign: .plus, exponent: shift, significand: 1)
    }
}
