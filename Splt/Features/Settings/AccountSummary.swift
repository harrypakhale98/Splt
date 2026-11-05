import SpltCore

/// What the Account header shows about you: your stored name.
struct AccountSummary: Equatable {
    var meID: PersonID?
    /// The name your person is stored under. Initials come from this, so you read the same everywhere.
    var meName: String?

    /// Reads the store. Anything that fails leaves that part empty.
    @MainActor
    static func load(from services: DataServices?) -> AccountSummary {
        guard let services else { return AccountSummary() }
        var summary = AccountSummary()
        let me = try? services.people.me()
        summary.meID = me?.id
        summary.meName = me?.name
        return summary
    }

    /// The name to show for you: the one you chose, else the one stored on your person, else "You".
    @MainActor
    func displayName(for profile: AccountProfile) -> String {
        profile.hasName ? profile.effectiveName : (meName ?? profile.effectiveName)
    }
}
