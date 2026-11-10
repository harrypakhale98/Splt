import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Account profile")
struct UIAccountProfileTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "splt.tests.profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func deviceNamesBecomeFirstNames() {
        #expect(AccountProfile.suggestedName(fromDeviceName: "Sam's iPhone") == "Sam")
        #expect(AccountProfile.suggestedName(fromDeviceName: "Sam Rivera\u{2019}s iPad") == "Sam Rivera")
        #expect(AccountProfile.suggestedName(fromDeviceName: "iPhone") == nil)
        #expect(AccountProfile.suggestedName(fromDeviceName: "Office's MacBook") == nil)
        #expect(AccountProfile.suggestedName(fromDeviceName: "Test 12's iPhone") == nil)
    }

    @Test func nameStartsFromTheDeviceAndFallsBackToYou() {
        #expect(AccountProfile(defaults: makeDefaults(), deviceName: "Priya's iPhone").displayName == "Priya")
        let blank = AccountProfile(defaults: makeDefaults(), deviceName: "iPhone")
        #expect(blank.displayName.isEmpty)
        #expect(blank.effectiveName == String(localized: "You"))
        #expect(!blank.hasName)
    }

    @Test func savedNameBeatsTheDeviceName() {
        let defaults = makeDefaults()
        let first = AccountProfile(defaults: defaults, deviceName: "Priya's iPhone")
        first.displayName = "  Sam  "
        first.save()
        let second = AccountProfile(defaults: defaults, deviceName: "Priya's iPhone")
        #expect(second.displayName == "Sam")
        #expect(defaults.string(forKey: AddFriendModel.inviteNameKey) == "Sam")
    }

    @Test func handlesPersistAndClear() {
        let defaults = makeDefaults()
        let profile = AccountProfile(defaults: defaults, deviceName: "iPhone")
        profile.setHandle("  @sam  ", for: .venmo)
        profile.setHandle("sam@okbank", for: .upi)
        profile.save()

        let reloaded = AccountProfile(defaults: defaults, deviceName: "iPhone")
        #expect(reloaded.handle(for: .venmo) == "@sam")
        #expect(reloaded.handle(for: .upi) == "sam@okbank")
        #expect(reloaded.handle(for: .cashApp).isEmpty)

        reloaded.setHandle("", for: .venmo)
        reloaded.save()
        #expect(AccountProfile(defaults: defaults, deviceName: "iPhone").handle(for: .venmo).isEmpty)
    }

    @Test func paymentLineNamesEachMethod() {
        let profile = AccountProfile(defaults: makeDefaults(), deviceName: "iPhone")
        #expect(profile.paymentLine == nil)
        profile.setHandle("sam", for: .venmo)
        profile.setHandle("$samr", for: .cashApp)
        let line = profile.paymentLine ?? ""
        #expect(line.contains("Venmo @sam"))
        #expect(line.contains("Cash App $samr"))
    }

    @Test func displayFormAddsTheUsualPrefix() {
        #expect(AccountProfile.displayForm(of: "@sam", method: .venmo) == "@sam")
        #expect(AccountProfile.displayForm(of: "sam", method: .cashApp) == "$sam")
        #expect(AccountProfile.displayForm(of: "sam", method: .paypal) == "paypal.me/sam")
        #expect(AccountProfile.displayForm(of: "sam@okbank", method: .upi) == "sam@okbank")
    }

    @Test func applyNameRenamesMeOnly() throws {
        let services = try DataServices.inMemory()
        let me = try services.people.ensureMe(name: "You")
        let profile = AccountProfile(defaults: makeDefaults(), deviceName: "iPhone")

        try profile.applyName(to: services.people)
        #expect(try services.people.me()?.name == "You")

        profile.displayName = "Sam"
        try profile.applyName(to: services.people)
        #expect(try services.people.me()?.id == me.id)
        #expect(try services.people.me()?.name == "Sam")
    }

    @Test func launchDoesNotUndoARenameMadeOnAnotherDevice() throws {
        let services = try DataServices.inMemory()
        try services.people.ensureMe(name: "Samuel, renamed elsewhere")
        let profile = AccountProfile(defaults: makeDefaults(), deviceName: "iPhone")
        profile.displayName = "Sam"
        try profile.applyNameIfNoProfile(to: services.people)
        #expect(try services.people.me()?.name == "Samuel, renamed elsewhere")
    }

    @Test func launchCreatesTheProfileWhenThereIsNone() throws {
        let services = try DataServices.inMemory()
        let profile = AccountProfile(defaults: makeDefaults(), deviceName: "iPhone")
        profile.displayName = "Sam"
        try profile.applyNameIfNoProfile(to: services.people)
        #expect(try services.people.me()?.name == "Sam")
    }

    /// A device that last knew you as Sam, after another device renamed you Samuel.
    private func renamedElsewhere(_ services: DataServices) throws -> AccountProfile {
        let profile = AccountProfile(defaults: makeDefaults(), deviceName: "iPhone")
        profile.displayName = "Sam"
        try profile.applyName(to: services.people)
        var me = try #require(try services.people.me())
        me.name = "Samuel"
        try services.people.update(me)
        return profile
    }

    @Test func closingTheEditorWithoutTypingDoesNotUndoARenameFromAnotherDevice() throws {
        let services = try DataServices.inMemory()
        let profile = try renamedElsewhere(services)
        profile.save()
        try profile.applyName(to: services.people)
        #expect(try services.people.me()?.name == "Samuel")
    }

    @Test func aRenameFromAnotherDeviceShowsHereAndCanBeChangedAgain() throws {
        let services = try DataServices.inMemory()
        let profile = try renamedElsewhere(services)
        let summary = AccountSummary.load(from: services, profile: profile)
        #expect(summary.displayName(for: profile) == "Samuel")
        #expect(profile.displayName == "Samuel")

        profile.displayName = "Sam"
        try profile.applyName(to: services.people)
        #expect(try services.people.me()?.name == "Sam")
    }

    @Test func goingBackToTheAccountScreenKeepsANameBeingTyped() throws {
        let services = try DataServices.inMemory()
        let profile = AccountProfile(defaults: makeDefaults(), deviceName: "iPhone")
        profile.displayName = "Sam"
        try profile.applyName(to: services.people)
        profile.displayName = "Sammy"
        _ = AccountSummary.load(from: services, profile: profile)
        #expect(profile.displayName == "Sammy")
        try profile.applyName(to: services.people)
        #expect(try services.people.me()?.name == "Sammy")
    }

    @Test func applyNameCreatesMeWhenMissing() throws {
        let services = try DataServices.inMemory()
        let profile = AccountProfile(defaults: makeDefaults(), deviceName: "iPhone")
        profile.displayName = "Sam"
        try profile.applyName(to: services.people)
        #expect(try services.people.me()?.name == "Sam")
    }
}
