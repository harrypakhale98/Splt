import Foundation

/// Keeps rate tables in memory and in a JSON file so conversions work offline.
///
/// The latest table per base goes stale after `latestFreshness`, but stays readable. Historical
/// rates never change, so they never expire. A missing or damaged file is treated as empty.
actor RatesCache {
    static let defaultLatestFreshness: TimeInterval = 12 * 3600
    static let historicalLimit = 400

    struct Latest: Sendable {
        var table: RateTable
        var isFresh: Bool
    }

    private struct Stored: Codable {
        var latest: [String: RateTable] = [:]
        var historical: [String: RateTable] = [:]
    }

    private let fileURL: URL?
    private let latestFreshness: TimeInterval
    private let now: @Sendable () -> Date
    private var stored = Stored()
    private var loaded = false

    /// - Parameter directory: where to keep `rates.json`; nil keeps everything in memory only.
    init(
        directory: URL?,
        latestFreshness: TimeInterval = RatesCache.defaultLatestFreshness,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = directory?.appendingPathComponent("rates.json")
        self.latestFreshness = latestFreshness
        self.now = now
    }

    /// The cache in the app's Application Support folder.
    static func standard(now: @escaping @Sendable () -> Date = { Date() }) -> RatesCache {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return RatesCache(directory: base?.appendingPathComponent("Rates", isDirectory: true), now: now)
    }

    func latest(base: String) -> Latest? {
        loadIfNeeded()
        guard let table = stored.latest[base.uppercased()] else { return nil }
        return Latest(table: table, isFresh: now().timeIntervalSince(table.fetchedAt) < latestFreshness)
    }

    func historical(base: String, day: String) -> RateTable? {
        loadIfNeeded()
        return stored.historical[Self.key(base, day)]
    }

    func storeLatest(_ table: RateTable) {
        loadIfNeeded()
        stored.latest[table.base] = table
        persist()
    }

    /// `day` is the day that was asked for, which can differ from the table's own day on weekends.
    func storeHistorical(_ table: RateTable, day: String) {
        loadIfNeeded()
        stored.historical[Self.key(table.base, day)] = table
        if stored.historical.count > Self.historicalLimit {
            let oldest = stored.historical.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
                .prefix(stored.historical.count - Self.historicalLimit)
            for entry in oldest { stored.historical[entry.key] = nil }
        }
        persist()
    }

    private static func key(_ base: String, _ day: String) -> String {
        base.uppercased() + "|" + day
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        stored = decoded
    }

    private func persist() {
        guard let fileURL else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(stored) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
