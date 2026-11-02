import Foundation

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

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: infinity, negativeInfinity: negativeInfinity, nan: notANumber
        )
        return try decoder.decode(type, from: data)
    }
}
