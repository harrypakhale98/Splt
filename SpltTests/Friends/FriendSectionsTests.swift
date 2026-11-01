import SpltCore
import Testing
@testable import Splt

@Suite("Friend sections")
struct FriendSectionsTests {
    @Test func sortsFriendsByWhoOwesWhom() {
        let sections = FriendSections(summaries: [
            summary("Ana", [usdAmount(500)]),
            summary("Ben", [usdAmount(-700)]),
            summary("Cy"),
            summary("Di", [usdAmount(300), Money(minorUnits: -100, currencyCode: "EUR")])
        ])
        #expect(sections.owesYou.map(\.person.name) == ["Ana"])
        #expect(sections.youOwe.map(\.person.name) == ["Ben"])
        #expect(sections.settled.map(\.person.name) == ["Cy"])
        #expect(sections.mixed.map(\.person.name) == ["Di"])
        #expect(sections.count == 4)
    }

    @Test func keepsTheOrderItWasGiven() {
        let sections = FriendSections(summaries: [summary("Zed", [usdAmount(100)]), summary("Amy", [usdAmount(900)])])
        #expect(sections.owesYou.map(\.person.name) == ["Zed", "Amy"])
    }

    @Test func searchMatchesEveryWordIgnoringCaseAndAccents() {
        let all = [summary("Jose Alvarez"), summary("Maria Gonzalez"), summary("Jo Smith")]
        #expect(FriendSections(summaries: all, query: "jos").settled.map(\.person.name) == ["Jose Alvarez"])
        #expect(FriendSections(summaries: all, query: "jose alv").count == 1)
        #expect(FriendSections(summaries: all, query: "JO").count == 2)
        #expect(FriendSections(summaries: all, query: "zzz").isEmpty)
        #expect(FriendSections(summaries: [summary("José")], query: "jose").count == 1)
    }

    @Test func leavesOutHiddenPeople() {
        let ana = summary("Ana", [usdAmount(500)])
        let ben = summary("Ben")
        let sections = FriendSections(summaries: [ana, ben], leftOut: [ana.id])
        #expect(sections.owesYou.isEmpty)
        #expect(sections.settled.map(\.person.name) == ["Ben"])
    }

    @Test func readsDirectionFromTheSigns() {
        #expect(FriendSections.direction(of: []) == .settled)
        #expect(FriendSections.direction(of: [usdAmount(1)]) == .owed)
        #expect(FriendSections.direction(of: [usdAmount(-1)]) == .owes)
        #expect(FriendSections.direction(of: [usdAmount(1), Money(minorUnits: -1, currencyCode: "EUR")]) == .mixed)
    }
}
