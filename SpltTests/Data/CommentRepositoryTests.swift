import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Comment repository")
struct CommentRepositoryTests {
    private func comment(_ fixture: Fixture, on expense: Expense?, text: String = "Nice") -> ExpenseComment {
        ExpenseComment(
            groupID: fixture.group.id, expenseID: expense?.id, authorID: fixture.sam.id, text: text,
            createdAt: fixture.clock.now()
        )
    }

    @Test func commentsListOldestFirst() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let first = comment(fixture, on: expense, text: "first")
        let second = comment(fixture, on: expense, text: "second")
        try fixture.services.comments.add(second)
        try fixture.services.comments.add(first)
        #expect(try fixture.services.comments.comments(on: expense.id).map(\.text) == ["first", "second"])
    }

    @Test func groupCommentsAreSeparateFromExpenseComments() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        try fixture.services.comments.add(comment(fixture, on: expense, text: "on expense"))
        try fixture.services.comments.add(comment(fixture, on: nil, text: "on group"))
        #expect(try fixture.services.comments.comments(in: fixture.group.id).map(\.text) == ["on group"])
        #expect(try fixture.services.comments.comments(on: expense.id).map(\.text) == ["on expense"])
    }

    @Test func addingACommentWritesActivityWithTheExpense() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Pizza")
        try fixture.services.comments.add(comment(fixture, on: expense, text: "Yum"))
        let latest = try #require(try fixture.services.activity.entries(in: fixture.group.id, limit: 1).first)
        let reference = ExpenseReference(id: expense.id, title: "Pizza", amount: usd(3000))
        #expect(latest.event == .commentAdded(expense: reference, text: "Yum"))
    }

    @Test func editingChangesTextAndStampsTheEditDate() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let original = comment(fixture, on: expense)
        try fixture.services.comments.add(original)
        try fixture.services.comments.edit(id: original.id, text: "Better")
        let stored = try #require(try fixture.services.comments.comments(on: expense.id).first)
        #expect(stored.text == "Better")
        #expect(stored.editedAt != nil)
    }

    @Test func deletingRemovesTheComment() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let original = comment(fixture, on: expense)
        try fixture.services.comments.add(original)
        try fixture.services.comments.delete(id: original.id)
        #expect(try fixture.services.comments.comments(on: expense.id).isEmpty)
        try fixture.services.comments.delete(id: original.id)
    }

    @Test func reactionsToggleOnAndOffPerPersonAndEmoji() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let original = comment(fixture, on: expense)
        try fixture.services.comments.add(original)
        func reactions() throws -> [CommentReaction] {
            try #require(try fixture.services.comments.comments(on: expense.id).first).reactions
        }
        try fixture.services.comments.toggleReaction("a", by: fixture.me.id, on: original.id)
        try fixture.services.comments.toggleReaction("a", by: fixture.priya.id, on: original.id)
        try fixture.services.comments.toggleReaction("b", by: fixture.me.id, on: original.id)
        #expect(try reactions().count == 3)
        try fixture.services.comments.toggleReaction("a", by: fixture.me.id, on: original.id)
        #expect(try reactions() == [
            CommentReaction(person: fixture.priya.id, emoji: "a"), CommentReaction(person: fixture.me.id, emoji: "b")
        ])
    }

    @Test func editingAnUnknownCommentThrows() throws {
        let fixture = try Fixture()
        #expect(throws: DataError.self) { try fixture.services.comments.edit(id: UUID(), text: "x") }
    }
}
