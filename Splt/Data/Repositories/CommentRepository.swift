import Foundation
import SpltCore

@MainActor
protocol CommentRepository {
    /// Oldest first.
    func comments(on expense: ExpenseID) throws -> [ExpenseComment]
    /// Comments on the group itself, oldest first.
    func comments(in group: GroupID) throws -> [ExpenseComment]
    func add(_ comment: ExpenseComment) throws
    func edit(id: UUID, text: String) throws
    func delete(id: UUID) throws
    /// Adds the reaction, or removes it if this person already reacted with the same emoji.
    func toggleReaction(_ emoji: String, by person: PersonID, on comment: UUID) throws
}
