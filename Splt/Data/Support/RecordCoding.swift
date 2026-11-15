import Foundation
import Synchronization

/// Encodes the Codable values stored as blobs. Keys are sorted so equal values give equal bytes.
enum RecordCoding {
    private static let infinity = "Infinity"
    private static let negativeInfinity = "-Infinity"
    private static let notANumber = "NaN"

    /// Encoding does not trap. Non finite numbers are written as text so nothing is rejected,
    /// and a value that still cannot be encoded becomes JSON `null`, which `decode` reports as
    /// a corrupt record instead of crashing.
    static func encode<Value: Encodable>(_ value: Value) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: infinity, negativeInfinity: negativeInfinity, nan: notANumber
        )
        return (try? encoder.encode(value)) ?? Data("null".utf8)
    }

    /// One decoder for every read: making a fresh one per blob cost more than decoding the blob.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: infinity, negativeInfinity: negativeInfinity, nan: notANumber
        )
        return decoder
    }()

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try decoder.decode(type, from: data)
    }

    /// Decodes a blob that is read again and again, such as an expense's payers and split on every refresh.
    /// The value is kept by its exact bytes, so a changed blob is always decoded afresh and never served stale.
    static func decodeKept<Value: Decodable & Sendable>(_ type: Value.Type, from data: Data) throws -> Value {
        let key = KeptKey(type: ObjectIdentifier(type), data: data)
        if let kept = kept.withLock({ $0[key] }) as? Value { return kept }
        let value = try decoder.decode(type, from: data)
        kept.withLock { store in
            // a ceiling, not a policy: past it the cache starts again, which only costs one more decode each
            if store.count >= mostKept { store.removeAll(keepingCapacity: true) }
            store[key] = value
        }
        return value
    }

    private struct KeptKey: Hashable, Sendable {
        let type: ObjectIdentifier
        let data: Data
    }

    private static let mostKept = 40_000
    private static let kept = Mutex<[KeptKey: any Sendable]>([:])
}
