/// Why a typed amount could not be read.
public enum MoneyParseError: Error, Equatable, Sendable {
    /// The text was blank.
    case empty
    /// The text is not a recognisable amount.
    case invalidFormat
    /// More decimals than the currency allows, for example "12.505" in USD or "12.5" in JPY.
    case tooManyFractionDigits
    /// A negative amount was typed where only positive amounts are allowed.
    case negativeNotAllowed
    /// The amount is too large to store.
    case outOfRange
}
