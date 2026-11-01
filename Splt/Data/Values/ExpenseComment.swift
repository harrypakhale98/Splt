import Foundation
import SpltCore

struct CommentReaction: Hashable, Sendable, Codable {
    var person: PersonID
    var emoji: String
}

/// A note left on an expense, or on a group when `expenseID` is nil.
struct ExpenseComment: Hashable, Sendable, Identifiable {
    var id: UUID
    var groupID: GroupID?
    var expenseID: ExpenseID?
    var authorID: PersonID
    var text: String
    var createdAt: Date
    var editedAt: Date?
    var reactions: [CommentReaction]

    init(
        id: UUID = UUID(),
        groupID: GroupID? = nil,
        expenseID: ExpenseID? = nil,
        authorID: PersonID,
        text: String,
        createdAt: Date = Date(),
        editedAt: Date? = nil,
        reactions: [CommentReaction] = []
    ) {
        self.id = id
        self.groupID = groupID
        self.expenseID = expenseID
        self.authorID = authorID
        self.text = text
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.reactions = reactions
    }
}
