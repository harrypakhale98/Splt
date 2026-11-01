import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Add friend")
struct AddFriendModelTests {
    private func model(_ services: DataServices) -> AddFriendModel {
        AddFriendModel(services: services, defaults: isolatedDefaults())
    }

    @Test func addsAPlaceholderByName() throws {
        let services = try DataServices.inMemory()
        let model = model(services)
        model.name = "  Maya   Chen "
        #expect(model.canAddByName)
        let result = try #require(model.addByName())
        guard case .created(let person) = result else { Issue.record("expected a new person"); return }
        #expect(person.name == "Maya Chen")
        #expect(person.kind == .placeholder)
        #expect(model.name.isEmpty)
        #expect(try services.people.friends().map(\.name) == ["Maya Chen"])
    }

    @Test func doesNotAddTheSameNameTwice() throws {
        let services = try DataServices.inMemory()
        let model = model(services)
        model.name = "Maya"
        _ = model.addByName()
        model.name = "maya"
        let result = try #require(model.addByName())
        guard case .existing = result else { Issue.record("expected the existing person"); return }
        #expect(try services.people.friends().count == 1)
    }

    @Test func emptyNamesAreRefused() throws {
        let services = try DataServices.inMemory()
        let model = model(services)
        model.name = "   "
        #expect(!model.canAddByName)
        #expect(model.addByName() == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func contactsBecomePlaceholdersWithAHint() throws {
        let services = try DataServices.inMemory()
        let model = model(services)
        let results = model.add(contacts: [
            MemberDraft(name: "Priya Nair", contactHint: "priya@example.com"),
            MemberDraft(name: "Diego")
        ])
        #expect(results.count == 2)
        let priya = try #require(try services.people.friends().first { $0.name == "Priya Nair" })
        #expect(priya.contactHint == "priya@example.com")
        #expect(priya.kind == .placeholder)
    }

    @Test func acceptingAnInviteKeepsTheSendersId() throws {
        let services = try DataServices.inMemory()
        let model = model(services)
        let id = UUID()
        let result = try #require(model.accept(FriendInvite(name: "Sam", personID: id)))
        #expect(result.person.id.rawValue == id)
        #expect(result.person.kind == .friend)
        guard case .existing = try #require(model.accept(FriendInvite(name: "Sam", personID: id))) else {
            Issue.record("expected the existing person the second time")
            return
        }
        #expect(try services.people.friends().count == 1)
    }

    @Test func anInviteFromYourselfIsRefused() throws {
        let services = try DataServices.inMemory()
        let me = try services.people.ensureMe(name: "Me")
        let model = model(services)
        #expect(model.accept(FriendInvite(name: "Me", personID: me.id.rawValue)) == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func theInviteNeedsYourName() throws {
        let services = try DataServices.inMemory()
        let me = try services.people.ensureMe(name: String(localized: "You"))
        let model = model(services)
        #expect(model.myInvite == nil)
        model.inviteName = "  Jamie "
        let invite = try #require(model.myInvite)
        #expect(invite.name == "Jamie")
        #expect(invite.personID == me.id.rawValue)
    }

    @Test func theInviteNameIsRemembered() throws {
        let services = try DataServices.inMemory()
        let defaults = isolatedDefaults()
        AddFriendModel(services: services, defaults: defaults).inviteName = "Jamie"
        #expect(AddFriendModel(services: services, defaults: defaults).inviteName == "Jamie")
    }
}
