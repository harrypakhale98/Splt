import Foundation
import SpltCore

enum GroupJSONExporter {
    static let formatVersion = 1

    struct Document: Codable {
        struct ExportedPerson: Codable {
            var id: PersonID
            var name: String
            var kind: PersonKind
        }

        var formatVersion: Int
        var exportedAt: Date
        var group: SplitGroup
        var people: [ExportedPerson]
        var expenses: [Expense]
        var payments: [Payment]
    }

    static func data(for snapshot: GroupExportSnapshot) throws -> Data {
        let document = Document(
            formatVersion: formatVersion,
            exportedAt: snapshot.exportedAt,
            group: snapshot.group,
            people: snapshot.people.map { .init(id: $0.id, name: $0.name, kind: $0.kind) },
            expenses: snapshot.expenses,
            payments: snapshot.payments
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Document.self, from: data)
    }
}
