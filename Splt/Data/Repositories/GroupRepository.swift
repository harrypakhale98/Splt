import Foundation
import SpltCore

@MainActor
protocol GroupRepository {
    /// Newest first.
    func groups(includeArchived: Bool) throws -> [SplitGroup]
    func group(id: GroupID) throws -> SplitGroup?
    func create(_ group: SplitGroup) throws
    /// Saves edits to the name, symbol, currency, dates, rate and debt simplification.
    /// Members change through `addMember` and `removeMember` so the activity feed stays accurate.
    func update(_ group: SplitGroup) throws
    func setArchived(_ archived: Bool, id: GroupID) throws
    /// Deletes the group and everything in it.
    func delete(id: GroupID) throws
    func addMember(_ person: PersonID, to group: GroupID) throws
    /// Throws `DataError.memberStillHasBalance` unless the person is settled up.
    func removeMember(_ person: PersonID, from group: GroupID) throws
    func balances(for group: GroupID) throws -> GroupBalances
    func export(group: GroupID, format: ExportFormat) throws -> Data
    /// Adds the expenses and settlements from a Splitwise CSV export. Members the group does not
    /// have yet are created as placeholders. Rows that cannot be rebuilt are reported, not stored.
    func importSplitwiseCSV(_ text: String, into group: GroupID) throws -> ImportSummary
}
