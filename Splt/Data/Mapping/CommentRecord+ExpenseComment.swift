import SpltCore

extension ExpenseComment {
    init(_ record: CommentRecord) {
        self.init(
            id: record.id,
            groupID: record.groupID.map { GroupID(rawValue: $0) },
            expenseID: record.expenseID.map { ExpenseID(rawValue: $0) },
            authorID: PersonID(rawValue: record.authorID),
            text: record.text,
            createdAt: record.createdAt,
            editedAt: record.editedAt,
            reactions: (try? RecordCoding.decode([CommentReaction].self, from: record.reactionsData)) ?? []
        )
    }
}

extension CommentRecord {
    convenience init(_ comment: ExpenseComment) {
        self.init(
            id: comment.id,
            groupID: comment.groupID?.rawValue,
            expenseID: comment.expenseID?.rawValue,
            authorID: comment.authorID.rawValue,
            text: comment.text,
            createdAt: comment.createdAt
        )
        editedAt = comment.editedAt
        reactionsData = RecordCoding.encode(comment.reactions)
    }

    func update(from comment: ExpenseComment) {
        text = comment.text
        editedAt = comment.editedAt
        reactionsData = RecordCoding.encode(comment.reactions)
    }
}
