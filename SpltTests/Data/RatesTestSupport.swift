import Foundation
import SpltCore
import Synchronization
@testable import Splt

/// Answers requests for a host from a closure, so provider tests never touch the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body = Data()
        var error: URLError?
    }

    private static let handlers = Mutex<[String: @Sendable (URLRequest) -> Reply]>([:])
    private static let seen = Mutex<[String: [URL]]>([:])

    static func register(host: String, _ handler: @escaping @Sendable (URLRequest) -> Reply) {
        handlers.withLock { $0[host] = handler }
    }

    static func requests(host: String) -> [URL] {
        seen.withLock { $0[host] ?? [] }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        Self.seen.withLock { $0[host, default: []].append(url) }
        let handler = Self.handlers.withLock { $0[host] }
        let reply = handler?(request) ?? Reply(status: 404)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A provider that returns canned tables and counts how often it is asked.
final class StubRatesProvider: RatesProvider {
    private struct State {
        var latest: [String: RateTable] = [:]
        var historical: [String: RateTable] = [:]
        var latestCalls = 0
        var historicalCalls = 0
    }

    private let state = Mutex(State())

    func setLatest(_ table: RateTable?, base: String) {
        state.withLock { $0.latest[base] = table }
    }

    func setHistorical(_ table: RateTable?, base: String, day: String) {
        state.withLock { $0.historical[base + "|" + day] = table }
    }

    var latestCalls: Int { state.withLock { $0.latestCalls } }
    var historicalCalls: Int { state.withLock { $0.historicalCalls } }

    func latest(base: String) async -> RateTable? {
        state.withLock { state in
            state.latestCalls += 1
            return state.latest[base]
        }
    }

    func historical(base: String, on day: String) async -> RateTable? {
        state.withLock { state in
            state.historicalCalls += 1
            return state.historical[base + "|" + day]
        }
    }
}

func table(
    _ base: String, day: String = "2026-03-02", fetchedAt: Date, rates: [String: Decimal]
) -> RateTable {
    RateTable(base: base, day: day, rates: rates, fetchedAt: fetchedAt)
}
