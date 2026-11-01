import Foundation

/// Reads ECB reference rates from the free Frankfurter service. No key, no account.
struct FrankfurterRatesProvider: RatesProvider {
    static let defaultBaseURL = URL(string: "https://api.frankfurter.dev/v1")!

    private let session: URLSession
    private let baseURL: URL
    private let now: @Sendable () -> Date

    init(session: URLSession? = nil, baseURL: URL = defaultBaseURL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session ?? Self.makeSession()
        self.baseURL = baseURL
        self.now = now
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }

    func latest(base: String) async -> RateTable? {
        await fetch(path: "latest", base: base)
    }

    func historical(base: String, on day: String) async -> RateTable? {
        guard Self.isDay(day) else { return nil }
        return await fetch(path: day, base: base)
    }

    private func fetch(path: String, base: String) async -> RateTable? {
        let base = base.uppercased()
        guard Self.isCurrencyCode(base),
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [URLQueryItem(name: "base", value: base)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.decode(data, expectedBase: base, fetchedAt: now())
    }

    /// Strict: anything that does not look exactly like a rates response is rejected.
    static func decode(_ data: Data, expectedBase: String, fetchedAt: Date) -> RateTable? {
        struct Response: Decodable {
            let base: String
            let date: String
            let rates: [String: Double]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.base.uppercased() == expectedBase.uppercased(),
              isDay(response.date),
              !response.rates.isEmpty else { return nil }
        var rates: [String: Decimal] = [:]
        for (code, value) in response.rates {
            guard isCurrencyCode(code), value.isFinite, value > 0,
                  let decimal = Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            rates[code.uppercased()] = decimal
        }
        return RateTable(base: expectedBase, day: response.date, rates: rates, fetchedAt: fetchedAt)
    }

    static func isCurrencyCode(_ text: String) -> Bool {
        text.count == 3 && text.allSatisfy { $0.isASCII && $0.isLetter }
    }

    static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && parts.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }
}
