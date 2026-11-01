import Foundation

/// One day's exchange rates against a base currency, as published by the ECB.
struct RateTable: Hashable, Sendable, Codable {
    var base: String
    /// The publication day as `yyyy-MM-dd`. Weekends and holidays carry the previous business day.
    var day: String
    /// Units of each currency that one unit of `base` buys.
    var rates: [String: Decimal]
    var fetchedAt: Date

    init(base: String, day: String, rates: [String: Decimal], fetchedAt: Date) {
        self.base = base.uppercased()
        self.day = day
        self.rates = rates
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey {
        case base, day, rates, fetchedAt
    }

    // Decimal is stored as text so a rate reads back exactly as it was written.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode([String: String].self, forKey: .rates)
        var rates: [String: Decimal] = [:]
        for (code, value) in text {
            guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(forKey: .rates, in: container, debugDescription: "Bad rate")
            }
            rates[code] = decimal
        }
        self.init(
            base: try container.decode(String.self, forKey: .base),
            day: try container.decode(String.self, forKey: .day),
            rates: rates,
            fetchedAt: try container.decode(Date.self, forKey: .fetchedAt)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(base, forKey: .base)
        try container.encode(day, forKey: .day)
        try container.encode(rates.mapValues { "\($0)" }, forKey: .rates)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }
}
