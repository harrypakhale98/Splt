import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Person palette")
struct UIPersonPaletteTests {
    private func ids(_ count: Int) -> [PersonID] {
        (0..<count).map { PersonID(rawValue: UUID(uuid: (UInt8($0), 7, 7, 7, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12))) }
    }

    @Test func preferredIndexIsStableAndInRange() {
        let person = PersonID(rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
        #expect(PersonPalette.preferredIndex(for: person) == PersonPalette.preferredIndex(for: person))
        for id in ids(50) { #expect((0..<PersonPalette.count).contains(PersonPalette.preferredIndex(for: id))) }
    }

    @Test func membersOfAGroupNeverShareAColorUpToTwelve() {
        for size in [2, 5, 8, 12] {
            let members = ids(size)
            let hues = PersonPalette.assignments(for: members).values
            #expect(Set(hues).count == size)
        }
    }

    @Test func moreThanTwelveMembersStillGetAColor() {
        let members = ids(15)
        let assigned = PersonPalette.assignments(for: members)
        #expect(assigned.count == 15)
        #expect(assigned.values.allSatisfy { (0..<12).contains($0) })
    }

    @Test func theFirstMemberKeepsTheirPreferredHue() {
        let members = ids(6)
        #expect(PersonPalette.assignments(for: members)[members[0]] == PersonPalette.preferredIndex(for: members[0]))
    }

    @Test func assignmentFollowsTheOrderOfMembers() {
        let members = ids(6)
        #expect(PersonPalette.assignments(for: members) == PersonPalette.assignments(for: members))
        #expect(PersonPalette.index(for: members[3], in: members) == PersonPalette.assignments(for: members)[members[3]])
    }

    @Test func aStrangerFallsBackToTheirPreferredHue() {
        let stranger = ids(1)[0]
        #expect(PersonPalette.index(for: stranger, in: []) == PersonPalette.preferredIndex(for: stranger))
    }

    @Test func duplicateMembersAreCountedOnce() {
        let members = ids(3)
        #expect(PersonPalette.assignments(for: members + members).count == 3)
    }

    @Test func hueLookupWraps() {
        #expect(PersonPalette.color(at: 12) == PersonPalette.color(at: 0))
        #expect(PersonPalette.color(at: -1) == PersonPalette.color(at: 11))
    }
}
