/// Why a currency conversion failed.
public enum ExchangeRatesError: Error, Equatable, Sendable {
    /// No rate is known between the two currencies.
    case missingRate(from: String, to: String)
    /// The converted amount does not fit in 64 bits.
    case overflow
}
