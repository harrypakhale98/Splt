import SpltCore

/// Adds amounts per currency. Amounts that cancel out are dropped. The result is sorted by currency.
enum MoneyTotals {
    static func sum(_ amounts: [Money]) -> [Money] {
        var units: [String: Int64] = [:]
        for amount in amounts {
            let (value, overflow) = units[amount.currencyCode, default: 0].addingReportingOverflow(amount.minorUnits)
            units[amount.currencyCode] = overflow ? (amount.minorUnits < 0 ? Int64.min : Int64.max) : value
        }
        return units.keys.sorted().compactMap { code in
            guard let value = units[code], value != 0 else { return nil }
            return Money(minorUnits: value, currencyCode: code)
        }
    }
}
