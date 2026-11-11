import CloudKit
import Foundation
import SpltCore

/// A person in a CloudKit share, reduced to what Splt needs.
struct ParticipantSnapshot: Equatable, Sendable {
    var userRecordName: String?
    var displayName: String?
    /// Email addresses and phone numbers the person was invited with.
    var contactHints: [String]
    var isCurrentUser: Bool
    var hasJoined: Bool
}

enum ParticipantMapper {
    static func snapshots(from share: CKShare) -> [ParticipantSnapshot] {
        share.participants.map { participant in
            let identity = participant.userIdentity
            let recordName = identity.userRecordID?.recordName
            let isCurrent = participant == share.currentUserParticipant || recordName == CKCurrentUserDefaultName
            let hints = [identity.lookupInfo?.emailAddress, identity.lookupInfo?.phoneNumber].compactMap { $0 }
            return ParticipantSnapshot(
                userRecordName: recordName == CKCurrentUserDefaultName ? nil : recordName,
                displayName: identity.nameComponents.map { $0.formatted(.name(style: .medium)) }.flatMap { $0.isEmpty ? nil : $0 },
                contactHints: hints,
                isCurrentUser: isCurrent,
                hasJoined: participant.acceptanceStatus == .accepted
            )
        }
    }
}

/// Makes sure everyone who joined a shared group exists as a person on this device.
@MainActor
struct ParticipantImporter {
    let services: DataServices

    /// Adds people for new participants.
    func importPeople(from snapshots: [ParticipantSnapshot], myUserRecordName: String?) throws {
        for snapshot in snapshots where snapshot.hasJoined && !snapshot.isCurrentUser {
            guard let recordName = snapshot.userRecordName, recordName != myUserRecordName else { continue }
            let id = CloudIdentity.personID(forUserRecordName: recordName)
            guard try services.people.person(id: id) == nil else { continue }
            try addStandIn(Person(
                id: id,
                name: snapshot.displayName ?? String(localized: "Friend"),
                contactHint: snapshot.contactHints.first,
                kind: .friend,
                claimedByCloudUserID: recordName
            ))
        }
    }

    /// A person known only from the share until their own record arrives. The oldest possible date means
    /// that record wins whenever it comes, so the name they chose is never replaced by this one.
    private func addStandIn(_ person: Person) throws {
        let record = PersonRecord(person)
        record.modifiedAt = .distantStandIn
        services.environment.context.insert(record)
        try services.environment.save()
    }

    /// Adds this person to a group they joined through a share, so everyone sees them as a member.
    /// It also repairs a join lost to a conflict, but it respects being removed: only a new invitation
    /// (`afterInvitation`) brings back someone whose latest word in the group's activity is a removal.
    /// Returns true when this person is a member of the group afterwards.
    @discardableResult
    func ensureMembership(ofMe userRecordName: String, inZone zoneName: String, afterInvitation: Bool = false) throws -> Bool {
        guard let groupID = UUID(uuidString: zoneName).map(GroupID.init(rawValue:)),
              let group = try services.groups.group(id: groupID) else { return false }
        let me = CloudIdentity.personID(forUserRecordName: userRecordName)
        guard !group.memberIDs.contains(me) else { return true }
        if !afterInvitation, try wasRemoved(me, from: groupID) { return false }
        if try services.people.me() == nil {
            // joined before choosing a name: the others know them from the share until they pick one
            try services.people.ensureMe(name: String(localized: "You"))
        }
        // a profile made just now, such as the name taken from an invite, uses the iCloud id from the start
        try IdentityAdopter(tracker: services.makeChangeTracker()).adopt(userRecordName: userRecordName)
        guard try services.people.person(id: me) != nil else { return false }
        try services.groups.addMember(me, to: groupID)
        return true
    }

    private func wasRemoved(_ person: PersonID, from group: GroupID) throws -> Bool {
        for entry in try services.activity.entries(in: group, limit: 1_000) {
            switch entry.event {
            case .memberRemoved(person): return true
            case .memberAdded(person): return false
            default: continue
            }
        }
        return false
    }
}

extension Date {
    /// The modified date of a stand in. Any real edit is later, and CloudKit can store it.
    fileprivate static let distantStandIn = Date(timeIntervalSince1970: 0)
}
