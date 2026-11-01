import SpltCore

/// "You owe" and "owed to you" as separate sums, one amount per currency, always positive.
struct BalanceTotals: Hashable, Sendable {
    var owedToYou: [Money]
    var youOwe: [Money]

    static let zero = BalanceTotals(owedToYou: [], youOwe: [])

    /// Builds the totals from signed amounts where positive means someone owes you.
    init(amounts: [Money]) {
        var owed: [Money] = []
        var owing: [Money] = []
        for amount in amounts {
            if amount.isPositive {
                owed.append(amount)
            } else if amount.isNegative {
                owing.append(Money(minorUnits: -amount.minorUnits, currencyCode: amount.currencyCode))
            }
        }
        owedToYou = MoneyTotals.sum(owed)
        youOwe = MoneyTotals.sum(owing)
    }

    init(owedToYou: [Money], youOwe: [Money]) {
        self.owedToYou = owedToYou
        self.youOwe = youOwe
    }

    var isSettled: Bool { owedToYou.isEmpty && youOwe.isEmpty }

    /// Both sums in one currency, or nil if a needed rate is missing.
    func converted(to currencyCode: String, rates: ExchangeRates) -> (owedToYou: Money, youOwe: Money)? {
        guard let owed = Self.convert(owedToYou, to: currencyCode, rates: rates),
              let owing = Self.convert(youOwe, to: currencyCode, rates: rates) else { return nil }
        return (owed, owing)
    }

    private static func convert(_ amounts: [Money], to currencyCode: String, rates: ExchangeRates) -> Money? {
        var total = Money.zero(currencyCode: currencyCode)
        for amount in amounts {
            guard let converted = try? rates.convert(amount, to: currencyCode),
                  let sum = try? total.adding(converted) else { return nil }
            total = sum
        }
        return total
    }
}
