import Foundation
import SpltCore
import Testing
import UIKit
@testable import Splt

@MainActor
@Suite("Group cover photos")
struct GroupCoverTests {
    private let covers = PhotoStore(
        directory: FileManager.default.temporaryDirectory.appending(path: "splt-covers-\(UUID().uuidString)")
    )

    private func photo(width: CGFloat = 40, height: CGFloat = 60) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func repository(_ fixture: Fixture) -> SwiftDataGroupRepository {
        SwiftDataGroupRepository(fixture.services.environment, covers: covers)
    }

    private func record(_ fixture: Fixture) throws -> GroupRecord {
        try #require(try fixture.services.environment.groupRecord(fixture.group.id))
    }

    @Test func settingACoverKeepsTheFileAndMarksTheGroupForUpload() async throws {
        let fixture = try Fixture()
        let before = try record(fixture).modifiedAt
        try await repository(fixture).setCover(photo(), for: fixture.group.id)

        let stored = try #require(try fixture.services.groups.group(id: fixture.group.id))
        let name = try #require(stored.coverFileName)
        #expect(covers.exists(name))
        #expect(covers.thumbnail(named: name) != nil)
        #expect(stored.shownCoverFileName == name)
        let updated = try record(fixture)
        #expect(updated.isDirty)
        #expect(updated.modifiedAt > before)
    }

    @Test func aLargePhotoIsShrunkLikeAReceipt() async throws {
        let fixture = try Fixture()
        try await repository(fixture).setCover(photo(width: 3000, height: 2400), for: fixture.group.id)
        let name = try #require(try fixture.services.groups.group(id: fixture.group.id)?.coverFileName)
        let data = try #require(covers.image(named: name))
        let image = try #require(UIImage(data: data))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= CGFloat(PhotoStore.maximumPixels))
    }

    @Test func replacingACoverDeletesTheOldFile() async throws {
        let fixture = try Fixture()
        let groups = repository(fixture)
        try await groups.setCover(photo(), for: fixture.group.id)
        let first = try #require(try fixture.services.groups.group(id: fixture.group.id)?.coverFileName)
        try await groups.setCover(photo(width: 80, height: 80), for: fixture.group.id)
        let second = try #require(try fixture.services.groups.group(id: fixture.group.id)?.coverFileName)
        #expect(first != second)
        #expect(!covers.exists(first))
        #expect(covers.exists(second))
    }

    @Test func removingACoverShowsTheSymbolAgain() async throws {
        let fixture = try Fixture()
        let groups = repository(fixture)
        try await groups.setCover(photo(), for: fixture.group.id)
        let name = try #require(try fixture.services.groups.group(id: fixture.group.id)?.coverFileName)
        try groups.removeCover(for: fixture.group.id)
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.coverFileName == nil)
        #expect(!covers.exists(name))
    }

    @Test func somethingThatIsNotAPhotoIsRefused() async throws {
        let fixture = try Fixture()
        await #expect(throws: UnreadablePhotoError.self) {
            try await repository(fixture).setCover(Data("not a photo".utf8), for: fixture.group.id)
        }
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.coverFileName == nil)
    }

    @Test func aFriendGroupNeverGetsACover() async throws {
        let fixture = try Fixture()
        let friendGroup = SplitGroup(name: "Sam", currencyCode: "USD", kind: .friend, memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(friendGroup)
        try await repository(fixture).setCover(photo(), for: friendGroup.id)
        #expect(try fixture.services.groups.group(id: friendGroup.id)?.coverFileName == nil)

        // even when a synced record names one, it isn't shown
        var named = friendGroup
        named.coverFileName = "cover.jpg"
        #expect(named.shownCoverFileName == nil)
    }

    @Test func anOlderCopyOfTheGroupDoesNotPutBackAReplacedCover() async throws {
        let fixture = try Fixture()
        let stale = try #require(try fixture.services.groups.group(id: fixture.group.id))
        try await repository(fixture).setCover(photo(), for: fixture.group.id)
        let name = try #require(try fixture.services.groups.group(id: fixture.group.id)?.coverFileName)

        var renamed = stale
        renamed.name = "Flat 4B"
        try fixture.services.groups.update(renamed)
        let stored = try #require(try fixture.services.groups.group(id: fixture.group.id))
        #expect(stored.name == "Flat 4B")
        #expect(stored.coverFileName == name)
    }

    @Test func theCoverAndDefaultSplitSurviveTheRecordMapping() {
        let sam = PersonID()
        let value = SplitGroup(
            name: "Lisbon", currencyCode: "EUR", coverFileName: "lisbon.jpg",
            defaultSplit: DefaultSplit(method: .shares, weights: [sam: 200])
        )
        #expect(SplitGroup(GroupRecord(value)) == value)
    }

    @Test func aCoverReachesTheOtherPhone() async throws {
        let phone = try PopulatedDevice()
        let groups = SwiftDataGroupRepository(phone.device.services.environment, covers: phone.device.photos.store(.covers))
        try await groups.setCover(photo(), for: phone.group.id)
        let name = try #require(try phone.device.services.groups.group(id: phone.group.id)?.coverFileName)
        let cloud = FakeCloud()
        try cloud.upload(from: phone.device)

        let other = try SyncDevice()
        try cloud.download(to: other)
        #expect(try other.services.groups.group(id: phone.group.id)?.coverFileName == name)
        #expect(other.photos.store(.covers).exists(name))
    }
}
