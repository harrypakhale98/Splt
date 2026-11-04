import CoreSpotlight
import Foundation
import SpltCore
import Synchronization
import Testing
import UIKit
@testable import Splt

private final class RecordingIndex: GroupSearchIndex, Sendable {
    struct Recorded: Equatable, Sendable {
        var identifier: String
        var description: String
    }

    private let recorded = Mutex<[[Recorded]]>([])

    var batches: [[Recorded]] { recorded.withLock { $0 } }

    func replaceAll(with items: [CSSearchableItem]) async throws {
        let batch = items.map {
            Recorded(identifier: $0.uniqueIdentifier, description: $0.attributeSet.contentDescription ?? "")
        }
        recorded.withLock { $0.append(batch) }
    }
}

private struct FailingIndex: GroupSearchIndex {
    struct Failure: Error {}
    func replaceAll(with items: [CSSearchableItem]) async throws { throw Failure() }
}

@Suite("Spotlight")
struct GroupSpotlightTests {
    @Test func identifiersRoundTrip() {
        let id = GroupID()
        let identifier = GroupSpotlight.identifier(for: id)
        #expect(identifier.hasPrefix("group."))
        #expect(GroupSpotlight.groupID(fromIdentifier: identifier) == id)
        #expect(GroupSpotlight.groupID(fromIdentifier: "expense.\(id)") == nil)
        #expect(GroupSpotlight.groupID(fromIdentifier: "group.not-a-uuid") == nil)
    }

    @Test func aTappedResultOpensItsGroup() {
        let id = GroupID()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: GroupSpotlight.identifier(for: id)]
        #expect(GroupSpotlight.groupID(from: activity) == id)
    }

    @Test func otherActivitiesAreIgnored() {
        let wrongType = NSUserActivity(activityType: "com.example.other")
        wrongType.userInfo = [CSSearchableItemActivityIdentifier: GroupSpotlight.identifier(for: GroupID())]
        #expect(GroupSpotlight.groupID(from: wrongType) == nil)

        let noInfo = NSUserActivity(activityType: CSSearchableItemActionType)
        #expect(GroupSpotlight.groupID(from: noInfo) == nil)
    }

    @Test func itemsCarryTheNameAndMembers() {
        let group = SplitGroup(name: "Lisbon Trip", symbol: "airplane", currencyCode: "EUR")
        let item = GroupSpotlight.item(for: group, memberNames: ["Maya", "Jonas"])
        #expect(item.uniqueIdentifier == GroupSpotlight.identifier(for: group.id))
        #expect(item.domainIdentifier == GroupSpotlight.domain)
        #expect(item.attributeSet.title == "Lisbon Trip")
        #expect(item.attributeSet.contentDescription?.contains("Maya, Jonas") == true)
        #expect(item.attributeSet.thumbnailData != nil)
    }

    @Test func onlyActiveGroupsPeopleMadeAreIndexed() {
        #expect(GroupSpotlight.isIndexed(SplitGroup(name: "A", currencyCode: "USD")))
        #expect(!GroupSpotlight.isIndexed(SplitGroup(name: "B", currencyCode: "USD", isArchived: true)))
        #expect(!GroupSpotlight.isIndexed(SplitGroup(name: "C", currencyCode: "USD", kind: .friend)))
    }

    @Test func theIndexerReplacesEverythingWithTheCurrentGroups() async {
        let me = Person(name: "Me", kind: .me)
        let maya = Person(name: "Maya")
        let trip = SplitGroup(name: "Trip", currencyCode: "EUR", memberIDs: [me.id, maya.id])
        let old = SplitGroup(name: "Old", currencyCode: "EUR", isArchived: true)
        let hidden = SplitGroup(name: "Maya", currencyCode: "EUR", kind: .friend)
        let index = RecordingIndex()

        let count = await GroupIndexer(index: index).update(
            groups: [trip, old, hidden], people: [me.id: me, maya.id: maya]
        )
        #expect(count == 1)
        let batches = index.batches
        #expect(batches.count == 1)
        #expect(batches.first?.map(\.identifier) == [GroupSpotlight.identifier(for: trip.id)])
        #expect(batches.first?.first?.description.contains("Maya") == true)
        #expect(batches.first?.first?.description.contains("Me") == false)
    }

    @Test func anEmptyListStillClearsTheIndex() async {
        let index = RecordingIndex()
        let count = await GroupIndexer(index: index).update(groups: [], people: [:])
        #expect(count == 0)
        #expect(index.batches.count == 1)
    }

    @Test func aFailingIndexIsNotFatal() async {
        let count = await GroupIndexer(index: FailingIndex()).update(
            groups: [SplitGroup(name: "A", currencyCode: "USD")], people: [:]
        )
        #expect(count == 0)
    }
}

@Suite("Invite")
struct GroupInviteTests {
    @Test func qrCodesAreSquareAndNotEmpty() throws {
        let image = try #require(QRCodeImage.make(from: "splt://group/\(UUID().uuidString)"))
        #expect(image.size.width > 0)
        #expect(image.size.width == image.size.height)
    }
}

@Suite("Group appearance")
struct GroupAppearanceTests {
    @Test func templatesMapToKinds() {
        #expect(GroupTemplate.standard.kind == .standard)
        #expect(GroupTemplate.home.kind == .standard)
        #expect(GroupTemplate.trip.kind == .trip)
        #expect(GroupTemplate.couple.kind == .couple)
        #expect(Set(GroupTemplate.allCases.map(\.defaultSymbol)).count == GroupTemplate.allCases.count)
    }

    @Test func errorsAreExplained() {
        let message = GroupErrorMessage.text(for: DataError.memberStillHasBalance(PersonID()))
        #expect(message.contains("Settle up"))
        #expect(!GroupErrorMessage.text(for: DataError.missingGroup).isEmpty)
    }
}
