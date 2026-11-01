import Foundation
import Testing
@testable import Splt

@Suite("Merge policy")
struct MergePolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func live(_ offset: TimeInterval, _ tie: String = "") -> SyncStamp {
        SyncStamp(modifiedAt: t0.addingTimeInterval(offset), tieBreaker: tie)
    }

    private func deleted(at offset: TimeInterval, modified: TimeInterval? = nil) -> SyncStamp {
        SyncStamp(
            modifiedAt: t0.addingTimeInterval(modified ?? offset), deletedAt: t0.addingTimeInterval(offset)
        )
    }

    @Test func laterEditWins() {
        #expect(MergePolicy.winner(local: live(10), remote: live(5)) == .local)
        #expect(MergePolicy.winner(local: live(5), remote: live(10)) == .remote)
    }

    @Test func equalTimesFallBackToTheTieBreaker() {
        #expect(MergePolicy.winner(local: live(5, "b"), remote: live(5, "a")) == .local)
        #expect(MergePolicy.winner(local: live(5, "a"), remote: live(5, "b")) == .remote)
    }

    @Test func bothDevicesPickTheSameWinner() {
        let first = live(5, "alpha")
        let second = live(5, "omega")
        let onDeviceOne = MergePolicy.winner(local: first, remote: second)
        let onDeviceTwo = MergePolicy.winner(local: second, remote: first)
        #expect(onDeviceOne == .remote)
        #expect(onDeviceTwo == .local)
    }

    @Test func tombstoneBeatsAnOlderEdit() {
        #expect(MergePolicy.winner(local: live(5), remote: deleted(at: 10)) == .remote)
        #expect(MergePolicy.winner(local: deleted(at: 10), remote: live(5)) == .local)
    }

    @Test func tombstoneBeatsAnEditMadeAtTheSameInstant() {
        #expect(MergePolicy.winner(local: live(10), remote: deleted(at: 10)) == .remote)
    }

    @Test func aNewerEditBeatsTheTombstone() {
        #expect(MergePolicy.winner(local: live(20), remote: deleted(at: 10)) == .local)
        #expect(MergePolicy.winner(local: deleted(at: 10), remote: live(20)) == .remote)
    }

    @Test func aTombstoneWinsEvenWhenTheOlderEditCameLast() {
        let edit = live(9)
        let tombstone = deleted(at: 10)
        #expect(MergePolicy.winner(local: tombstone, remote: edit) == .local)
        #expect(MergePolicy.winner(local: edit, remote: tombstone) == .remote)
    }

    @Test func twoTombstonesTakeTheLaterOne() {
        #expect(MergePolicy.winner(local: deleted(at: 10), remote: deleted(at: 20)) == .remote)
        #expect(MergePolicy.winner(local: deleted(at: 20), remote: deleted(at: 10)) == .local)
    }

    @Test func aRestoredCopyBeatsItsOwnOlderTombstone() {
        let tombstone = deleted(at: 10)
        let restored = SyncStamp(modifiedAt: t0.addingTimeInterval(11))
        #expect(MergePolicy.winner(local: restored, remote: tombstone) == .local)
    }
}
