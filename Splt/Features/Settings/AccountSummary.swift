import SpltCore

/// What the Account header shows about you: your stored name and who you split with.
struct AccountSummary: Equatable {
    var meID: PersonID?
    /// The name your person is stored under. Initials come from this, so you read the same everywhere.
    var meName: String?
    var groupCount = 0
    var friendCount = 0
    var friendIDs: [PersonID] = []
    var orbitNames: [String] = []

    /// Reads the store. Anything that fails leaves that part empty.
    @MainActor
    static func load(from services: DataServices?) -> AccountSummary {
        guard let services else { return AccountSummary() }
        var summary = AccountSummary()
        let me = try? services.people.me()
        summary.meID = me?.id
        summary.meName = me?.name
        let friends = (try? services.people.friends()) ?? []
        summary.friendCount = friends.count
        summary.friendIDs = friends.map(\.id)
        summary.orbitNames = friends.prefix(5).map(\.name)
        summary.groupCount = ((try? services.groups.groups(includeArchived: false)) ?? [])
            .filter { $0.kind != .friend }.count
        return summary
    }

    /// The name to show for you: the one you chose, else the one stored on your person, else "You".
    @MainActor
    func displayName(for profile: AccountProfile) -> String {
        profile.hasName ? profile.effectiveName : (meName ?? profile.effectiveName)
    }

    /// The hue of your orbit dots: real friends keep their own color.
    var orbitHues: [Int]? {
        let hues = friendIDs.prefix(5).map { PersonPalette.index(for: $0) }
        return hues.isEmpty ? nil : Array(hues)
    }
}
