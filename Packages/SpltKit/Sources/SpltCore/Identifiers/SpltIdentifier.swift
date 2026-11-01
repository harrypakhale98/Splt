import Foundation

/// Shared behaviour of the UUID backed identifiers.
///
/// Identifiers encode as a plain UUID string and, as dictionary keys, as JSON object keys.
/// They order by UUID string so any code that must be deterministic can sort them.
public protocol SpltIdentifier: Hashable, Sendable, Codable, Comparable, CustomStringConvertible, CodingKeyRepresentable {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

extension SpltIdentifier {
    /// A new random identifier.
    public init() {
        self.init(rawValue: UUID())
    }

    /// An identifier from a UUID string, or nil if the string is not a UUID.
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }

    public var description: String { rawValue.uuidString }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }

    public var codingKey: any CodingKey {
        IdentifierCodingKey(stringValue: rawValue.uuidString)
    }

    public init?<Key: CodingKey>(codingKey: Key) {
        self.init(uuidString: codingKey.stringValue)
    }
}

private struct IdentifierCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}
