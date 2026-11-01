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

/// A guess that an existing placeholder is the same person as someone who joined.
struct ClaimSuggestion: Equatable, Sendable {
    var placeholder: PersonID
    var participant: PersonID
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

    /// Adds people for new participants and returns suggestions for placeholders that look like them.
    @discardableResult
    func importPeople(from snapshots: [ParticipantSnapshot], myUserRecordName: String?) throws -> [ClaimSuggestion] {
        var suggestions: [ClaimSuggestion] = []
        let existing = try services.people.allPeople()
        for snapshot in snapshots where snapshot.hasJoined && !snapshot.isCurrentUser {
            guard let recordName = snapshot.userRecordName, recordName != myUserRecordName else { continue }
            let id = CloudIdentity.personID(forUserRecordName: recordName)
            guard try services.people.person(id: id) == nil else { continue }
            let hints = Set(snapshot.contactHints.map { $0.lowercased() })
            try services.people.add(Person(
                id: id,
                name: snapshot.displayName ?? String(localized: "Friend"),
                contactHint: snapshot.contactHints.first,
                kind: .friend,
                claimedByCloudUserID: recordName
            ))
            for person in existing where person.kind != .me && person.id != id {
                guard let hint = person.contactHint?.lowercased(), hints.contains(hint) else { continue }
                suggestions.append(ClaimSuggestion(placeholder: person.id, participant: id))
            }
        }
        return suggestions
    }

    /// Adds this person to a group they joined through a share, once, so everyone sees them as a member.
    func ensureMembership(ofMe userRecordName: String, inZone zoneName: String) throws {
        guard let groupID = UUID(uuidString: zoneName).map(GroupID.init(rawValue:)),
              let group = try services.groups.group(id: groupID) else { return }
        let me = CloudIdentity.personID(forUserRecordName: userRecordName)
        guard try services.people.person(id: me) != nil, !group.memberIDs.contains(me) else { return }
        try services.groups.addMember(me, to: groupID)
    }
}
