import SpltCore

@MainActor
protocol PersonRepository {
    /// The owner of this device, if the profile exists yet.
    func me() throws -> Person?
    /// Returns the current user, creating the profile with `name` on first use.
    @discardableResult func ensureMe(name: String) throws -> Person
    func person(id: PersonID) throws -> Person?
    /// People in the order of `ids`. Unknown ids are skipped.
    func people(ids: [PersonID]) throws -> [Person]
    /// Everyone, sorted by name.
    func allPeople() throws -> [Person]
    /// Everyone except the current user, sorted by name.
    func friends() throws -> [Person]
    func add(_ person: Person) throws
    func update(_ person: Person) throws
    /// Turns a placeholder into a friend who owns the given iCloud user.
    func claim(_ id: PersonID, cloudUserID: String) throws
    func delete(id: PersonID) throws
    /// What one friend owes you across every group.
    func friendBalance(with friend: PersonID) throws -> FriendBalance
    /// A balance for every friend you share a group with, sorted by friend name.
    func friendBalances() throws -> [FriendBalance]
}
