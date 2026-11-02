import Foundation
import SpltCore

extension ExpenseFormModel {
    /// Changes when the currency, the expense day or the group changes, to restart the rate lookup.
    var rateKey: String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(group?.id.description ?? "")|\(currencyCode)|\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }

    /// The rates to convert with: the lookup for this day and currency once it has finished,
    /// until then whatever the app already holds.
    var activeRates: ExchangeRates? {
        guard let group else { return nil }
        if let fetchedRates, fetchedRates.key == rateKey, let rates = fetchedRates.rates { return rates }
        return (dependencies.rates ?? services.expenseRates).rates(group)
    }

    /// The group amount for the typed amount, when the currencies differ and a rate is known.
    var convertedTotal: Money? {
        guard let total, let group, currencyCode != group.currencyCode, let rates = activeRates else { return nil }
        return try? rates.convert(total, to: group.currencyCode)
    }

    /// True when the expense is in another currency but no rate is known to show its value.
    var lacksRate: Bool {
        guard total != nil, let group, currencyCode != group.currencyCode, !isFindingRate else { return false }
        return convertedTotal == nil
    }

    var rateText: String? {
        guard let group, currencyCode != group.currencyCode,
              let rate = activeRates?.rate(from: currencyCode, to: group.currencyCode) else { return nil }
        let value = rate.formatted(.number.locale(locale).precision(.significantDigits(2...6)))
        return String(localized: "1 \(currencyCode) = \(value) \(group.currencyCode)")
    }

    /// Finds the rate for the expense date in the background. Pinned group rate first, then the
    /// rate published for that day, then the latest. Saving never waits for it and an offline
    /// failure just leaves no converted value.
    func refreshRate() async {
        guard let group, currencyCode != group.currencyCode else {
            fetchedRates = nil
            isFindingRate = false
            return
        }
        let key = rateKey
        if fetchedRates?.key == key, fetchedRates?.rates != nil { return }
        isFindingRate = true
        let code = currencyCode
        let day = date
        let found: ExchangeRates?
        if let lookup = dependencies.rateLookup {
            found = await lookup(group, day, code)
        } else {
            found = await services.rates.exchangeRates(for: group, on: day, from: code)
        }
        guard !Task.isCancelled, key == rateKey else { return }
        fetchedRates = (key, found)
        isFindingRate = false
    }
}
