import Foundation
import Testing
@testable import SpltCore

@Suite("Identifiers")
struct IdentifierTests {
    private let uuid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func newIdentifiersAreUnique() {
        #expect(PersonID() != PersonID())
        #expect(GroupID() != GroupID())
        #expect(ExpenseID() != ExpenseID())
        #expect(PaymentID() != PaymentID())
    }

    @Test func wrapsAUUID() {
        #expect(PersonID(rawValue: uuid).rawValue == uuid)
        #expect(PersonID(rawValue: uuid) == PersonID(rawValue: uuid))
        #expect(PersonID(rawValue: uuid).description == uuid.uuidString)
    }

    @Test func buildsFromStrings() {
        #expect(GroupID(uuidString: uuid.uuidString)?.rawValue == uuid)
        #expect(GroupID(uuidString: "not a uuid") == nil)
    }

    @Test func encodesAsAPlainUUIDString() throws {
        let data = try JSONEncoder().encode([ExpenseID(rawValue: uuid)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"\(uuid.uuidString)\"]")
    }

    @Test func codableRoundTrip() throws {
        let id = PaymentID()
        let decoded = try JSONDecoder().decode(PaymentID.self, from: JSONEncoder().encode(id))
        #expect(decoded == id)
    }

    @Test func dictionariesEncodeAsObjectsKeyedByUUID() throws {
        let person = PersonID(rawValue: uuid)
        let original = [person: Money(minorUnits: 250, currencyCode: "USD")]
        let data = try JSONEncoder().encode(original)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json.keys.contains(uuid.uuidString))
        let decoded = try JSONDecoder().decode([PersonID: Money].self, from: data)
        #expect(decoded == original)
    }

    @Test func orderingIsStableAndTotal() {
        let low = PersonID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let high = PersonID(rawValue: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!)
        #expect(low < high)
        #expect([high, low].sorted() == [low, high])
    }

    @Test func differentKindsAreDifferentTypes() {
        let person = PersonID(rawValue: uuid)
        let group = GroupID(rawValue: uuid)
        #expect(person.rawValue == group.rawValue)
        #expect(type(of: person) != type(of: group))
    }
}
