import Foundation
import SpltCore
import Synchronization
import Testing
@testable import Splt

@MainActor
@Suite("Invite link")
struct InviteLinkModelTests {
    /// Sharing that counts how often the link was asked for, which is what opens a share.
    private final class CountingSharing: GroupSharing {
        static let link = URL(string: "https://www.icloud.com/share/abc")!
        private let inviteOnly: Bool
        private let failure: SyncError?
        private let asked = Mutex(0)

        init(inviteOnly: Bool, failure: SyncError? = nil) {
            self.inviteOnly = inviteOnly
            self.failure = failure
        }

        var linkRequests: Int { asked.withLock { $0 } }

        func inviteURL(for groupID: GroupID, groupName: String) async throws -> URL {
            asked.withLock { $0 += 1 }
            return Self.link
        }

        func isInviteOnly(groupID: GroupID) async throws -> Bool {
            if let failure { throw failure }
            return inviteOnly
        }

        func leave(groupID: GroupID) async throws {}
        func isSharedByMe(groupID: GroupID) async -> Bool { true }
    }

    private func makeModel() -> InviteLinkModel {
        InviteLinkModel(groupID: GroupID(), groupName: "Lisbon Trip")
    }

    @Test func aGroupThatIsNotLimitedShowsItsLinkStraightAway() async {
        let sharing = CountingSharing(inviteOnly: false)
        let model = makeModel()
        #expect(model.state == .loading)
        await model.load(using: sharing)
        #expect(model.state == .ready(CountingSharing.link))
        #expect(sharing.linkRequests == 1)
    }

    @Test func openingTheScreenLeavesAnInviteOnlyShareAlone() async {
        let sharing = CountingSharing(inviteOnly: true)
        let model = makeModel()
        await model.load(using: sharing)
        #expect(model.state == .inviteOnly)
        #expect(sharing.linkRequests == 0)
    }

    @Test func theLinkIsMadeOnceTheOwnerAsksForIt() async {
        let sharing = CountingSharing(inviteOnly: true)
        let model = makeModel()
        await model.load(using: sharing)
        await model.openToAnyone(using: sharing)
        #expect(model.state == .ready(CountingSharing.link))
        #expect(sharing.linkRequests == 1)
    }

    @Test func aShareThatCannotBeCheckedIsNotOpened() async {
        let sharing = CountingSharing(inviteOnly: false, failure: .notReady)
        let model = makeModel()
        await model.load(using: sharing)
        #expect(model.state == .failed(SyncError.notReady.localizedDescription))
        #expect(sharing.linkRequests == 0)
    }
}
