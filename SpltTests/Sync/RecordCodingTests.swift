import Foundation
import Testing
@testable import Splt

@Suite("Record coding")
struct RecordCodingTests {
    private struct Sample: Codable, Equatable {
        var name: String
        var ratio: Double
    }

    @Test func valuesRoundTripWithSortedKeys() throws {
        let value = Sample(name: "Dinner", ratio: 0.5)
        let data = RecordCoding.encode(value)
        #expect(String(decoding: data, as: UTF8.self) == "{\"name\":\"Dinner\",\"ratio\":0.5}")
        #expect(try RecordCoding.decode(Sample.self, from: data) == value)
    }

    @Test func nonFiniteNumbersAreStoredInsteadOfRejected() throws {
        let infinite = try RecordCoding.decode(Sample.self, from: RecordCoding.encode(Sample(name: "a", ratio: .infinity)))
        #expect(infinite.ratio == .infinity)
        let negative = try RecordCoding.decode(Sample.self, from: RecordCoding.encode(Sample(name: "a", ratio: -.infinity)))
        #expect(negative.ratio == -.infinity)
        let nan = try RecordCoding.decode(Sample.self, from: RecordCoding.encode(Sample(name: "a", ratio: .nan)))
        #expect(nan.ratio.isNaN)
    }

    @Test func aValueThatCannotBeEncodedBecomesNullInsteadOfCrashing() {
        struct Refuses: Encodable {
            func encode(to encoder: any Encoder) throws {
                throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "no"))
            }
        }
        let data = RecordCoding.encode(Refuses())
        #expect(String(decoding: data, as: UTF8.self) == "null")
        #expect(throws: (any Error).self) { try RecordCoding.decode(Sample.self, from: data) }
    }

    @Test func fieldTextIsStableForEveryKindOfValue() {
        var fields = SyncFields()
        fields.set("b", Int64(2))
        fields.set("a", "x")
        fields.set("c", 1.5)
        fields.set("d", Date(timeIntervalSinceReferenceDate: 10))
        fields.set("e", Data([1, 2]))
        let text = fields.canonicalText
        #expect(text.split(separator: "\n").map { $0.prefix(2) } == ["a=", "b=", "c=", "d=", "e="])
        #expect(text == fields.canonicalText)
        #expect(SyncFields().canonicalText.isEmpty)
    }
}
