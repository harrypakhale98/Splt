import Foundation

/// The domain fields of one record as plain values, keyed by field name.
///
/// A missing key means the optional field is nil. Bookkeeping such as the modified date and
/// the tombstone travels in `SyncPayload`, not here.
struct SyncFields: Hashable, Sendable {
    private(set) var values: [String: SyncValue]

    init(_ values: [String: SyncValue] = [:]) {
        self.values = values
    }

    mutating func set(_ key: String, _ value: String?) {
        values[key] = value.map(SyncValue.string)
    }

    mutating func set(_ key: String, _ value: Int64?) {
        values[key] = value.map(SyncValue.int)
    }

    mutating func set(_ key: String, _ value: Double?) {
        values[key] = value.map(SyncValue.double)
    }

    mutating func set(_ key: String, _ value: Date?) {
        values[key] = value.map(SyncValue.date)
    }

    mutating func set(_ key: String, _ value: Data?) {
        values[key] = value.map(SyncValue.data)
    }

    mutating func set(_ key: String, _ value: Bool) {
        values[key] = .int(value ? 1 : 0)
    }

    mutating func set(_ key: String, _ value: UUID?) {
        values[key] = value.map { .string($0.uuidString) }
    }

    func string(_ key: String) -> String? {
        if case .string(let value) = values[key] { value } else { nil }
    }

    func int(_ key: String) -> Int64? {
        if case .int(let value) = values[key] { value } else { nil }
    }

    func double(_ key: String) -> Double? {
        if case .double(let value) = values[key] { value } else { nil }
    }

    func date(_ key: String) -> Date? {
        if case .date(let value) = values[key] { value } else { nil }
    }

    func data(_ key: String) -> Data? {
        if case .data(let value) = values[key] { value } else { nil }
    }

    func bool(_ key: String) -> Bool {
        int(key) == 1
    }

    func uuid(_ key: String) -> UUID? {
        string(key).flatMap(UUID.init(uuidString:))
    }

    /// A stable text form, used to break ties the same way on every device.
    var canonicalText: String {
        values.keys.sorted().map { key in
            let text: String
            switch values[key]! {
            case .string(let value): text = "s:" + value
            case .int(let value): text = "i:" + String(value)
            case .double(let value): text = "d:" + String(value.bitPattern)
            case .date(let value): text = "t:" + String(value.timeIntervalSinceReferenceDate.bitPattern)
            case .data(let value): text = "b:" + value.base64EncodedString()
            }
            return key + "=" + text
        }.joined(separator: "\n")
    }
}
