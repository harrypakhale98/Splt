import Foundation

/// Finds UUIDs written as text, so references can be followed through JSON blobs without knowing their shape.
enum UUIDScanner {
    private static let length = 36

    static func uuids(in data: Data) -> Set<String> {
        var found: Set<String> = []
        let bytes = [UInt8](data)
        guard bytes.count >= length else { return found }
        var index = 0
        while index + length <= bytes.count {
            if looksLikeUUID(bytes, at: index) {
                let slice = bytes[index..<index + length]
                found.insert(String(decoding: slice, as: UTF8.self).uppercased())
                index += length
            } else {
                index += 1
            }
        }
        return found
    }

    static func uuids(in text: String) -> Set<String> {
        uuids(in: Data(text.utf8))
    }

    private static func looksLikeUUID(_ bytes: [UInt8], at start: Int) -> Bool {
        for offset in 0..<length {
            let byte = bytes[start + offset]
            if offset == 8 || offset == 13 || offset == 18 || offset == 23 {
                if byte != UInt8(ascii: "-") { return false }
            } else if !isHex(byte) {
                return false
            }
        }
        return true
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
    }
}

extension SyncFields {
    /// Every UUID mentioned by a string or blob field.
    var referencedUUIDs: Set<String> {
        var found: Set<String> = []
        for value in values.values {
            switch value {
            case .string(let text): found.formUnion(UUIDScanner.uuids(in: text))
            case .data(let data): found.formUnion(UUIDScanner.uuids(in: data))
            case .int, .double, .date: break
            }
        }
        return found
    }
}
