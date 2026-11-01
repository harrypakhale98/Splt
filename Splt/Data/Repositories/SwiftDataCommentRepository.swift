import Foundation
import SpltCore
import SwiftData

@MainActor
final class SwiftDataCommentRepository: CommentRepository {
    private let env: RepositoryContext

    init(_ env: RepositoryContext) {
        self.env = env
    }

    func comments(on expense: ExpenseID) throws -> [ExpenseComment] {
        let eid: UUID? = expense.rawValue
        let descriptor = FetchDescriptor<CommentRecord>(
            predicate: #Predicate { $0.expenseID == eid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try env.context.fetch(descriptor).map(ExpenseComment.init)
    }

    func comments(in group: GroupID) throws -> [ExpenseComment] {
        let gid: UUID? = group.rawValue
        let descriptor = FetchDescriptor<CommentRecord>(
            predicate: #Predicate { $0.groupID == gid && $0.expenseID == nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try env.context.fetch(descriptor).map(ExpenseComment.init)
    }

    func add(_ comment: ExpenseComment) throws {
        guard try CommentRecord.find(recordName: comment.id.uuidString, in: env.context) == nil else {
            throw DataError.alreadyExists("comment \(comment.id)")
        }
        var reference: ExpenseReference?
        if let expenseID = comment.expenseID, let record = try env.expenseRecord(expenseID) {
            reference = SwiftDataExpenseRepository.reference(try Expense(record))
        }
        let record = CommentRecord(comment)
        env.context.insert(record)
        env.tracker.recordEdit(record)
        try env.log(.commentAdded(expense: reference, text: comment.text), groupID: comment.groupID)
        try env.save()
    }

    func edit(id: UUID, text: String) throws {
        let record = try find(id)
        guard record.text != text else { return }
        record.text = text
        record.editedAt = env.now()
        env.tracker.recordEdit(record)
        try env.save()
    }

    func delete(id: UUID) throws {
        guard let record = try CommentRecord.find(recordName: id.uuidString, in: env.context),
              record.deletedAt == nil else { return }
        env.tracker.tombstone(record)
        try env.save()
    }

    func toggleReaction(_ emoji: String, by person: PersonID, on comment: UUID) throws {
        let record = try find(comment)
        var reactions = ExpenseComment(record).reactions
        let reaction = CommentReaction(person: person, emoji: emoji)
        if let index = reactions.firstIndex(of: reaction) {
            reactions.remove(at: index)
        } else {
            reactions.append(reaction)
        }
        record.reactionsData = RecordCoding.encode(reactions)
        env.tracker.recordEdit(record)
        try env.save()
    }

    private func find(_ id: UUID) throws -> CommentRecord {
        guard let record = try CommentRecord.find(recordName: id.uuidString, in: env.context),
              record.deletedAt == nil else { throw DataError.notFound("comment \(id)") }
        return record
    }
}
