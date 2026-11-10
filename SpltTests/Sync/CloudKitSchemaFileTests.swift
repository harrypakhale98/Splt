import Foundation
import Testing
@testable import Splt

/// `Config/CloudKitSchema.ckdb` is what gets imported into the CloudKit Dashboard and deployed to
/// Production. Production never adds a field on its own, so a field the app writes that is missing from
/// the file fails to sync once the app ships. This keeps the file in step with `RecordSchema`.
@Suite("CloudKit schema file")
struct CloudKitSchemaFileTests {
    private static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/CloudKitSchema.ckdb")

    private static func ckdbType(_ kind: FieldKind) -> String {
        switch kind {
        case .string: "STRING"
        case .int: "INT64"
        case .double: "DOUBLE"
        case .date: "TIMESTAMP"
        case .data: "BYTES"
        }
    }

    /// The app's own fields of each record type in the file, by name, leaving out CloudKit's `___` fields.
    private static func fileTypes() throws -> [String: [String: String]] {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let typePattern = try NSRegularExpression(pattern: #"RECORD TYPE (\w+) \((.*?)\);"#, options: .dotMatchesLineSeparators)
        let fieldPattern = try NSRegularExpression(pattern: #"^\s*"(\w+)"\s+([A-Z0-9<>]+),?\s*$"#, options: .anchorsMatchLines)
        var types: [String: [String: String]] = [:]
        let whole = NSRange(text.startIndex..., in: text)
        for match in typePattern.matches(in: text, range: whole) {
            let name = String(text[Range(match.range(at: 1), in: text)!])
            let body = String(text[Range(match.range(at: 2), in: text)!])
            var fields: [String: String] = [:]
            for field in fieldPattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                let key = String(body[Range(field.range(at: 1), in: body)!])
                guard !key.hasPrefix("___") else { continue }
                fields[key] = String(body[Range(field.range(at: 2), in: body)!])
            }
            types[name] = fields
        }
        return types
    }

    @Test("every synced record type and field is in the file with the right type")
    func fileMatchesRecordSchema() throws {
        let types = try Self.fileTypes()
        for type in SyncRecordType.allCases {
            let inFile = try #require(types[type.rawValue], "\(type.rawValue) is missing from CloudKitSchema.ckdb")
            var expected = RecordSchema.fields(for: type).mapValues(Self.ckdbType)
            expected[RecordSchema.modifiedAtKey] = "TIMESTAMP"
            expected[RecordSchema.deletedAtKey] = "TIMESTAMP"
            expected[RecordSchema.schemaVersionKey] = "INT64"
            #expect(inFile == expected, "\(type.rawValue) in CloudKitSchema.ckdb differs from RecordSchema")
        }
    }
}
