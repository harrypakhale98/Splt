import Foundation

/// Encodes the Codable values stored as blobs. Keys are sorted so equal values give equal bytes.
enum RecordCoding {
    static func encode<Value: Encodable>(_ value: Value) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(value)
        } catch {
            preconditionFailure("A record value failed to encode: \(error)")
        }
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }
}
