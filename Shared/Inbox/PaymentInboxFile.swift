import Foundation

/// The inbox on disk. One small JSON file, shared through the app group so the share extension
/// and the widgets see the same payments. It is readable while the phone is locked once it has been
/// unlocked after a restart, because Wallet hands payments over at the checkout.
struct PaymentInboxFile: Sendable {
    static let appGroupID = "group.com.harrypakhale.splt"
    /// How many payments the app counts as worth asking about, for the widgets.
    static let toSplitCountKey = "inbox.toSplitCount"

    let url: URL

    /// The app group's file, or one in Application Support when the build has no app group.
    static var shared: PaymentInboxFile {
        let manager = FileManager.default
        let folder = manager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PaymentInboxFile(url: folder.appending(path: "PaymentInbox.json"))
    }

    /// Defaults shared with the extensions, or the standard ones without an app group.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    func read() -> PaymentInboxState {
        var state = PaymentInboxState()
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            state = Self.decode(at: url)
        }
        return state
    }

    /// Reads, changes and writes the file in one step, so the app and an extension never overwrite each other.
    @discardableResult
    func update<Result>(_ change: (inout PaymentInboxState) -> Result) -> Result? {
        var result: Result?
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { url in
            var state = Self.decode(at: url)
            result = change(&state)
            Self.write(state, to: url)
        }
        return result
    }

    private static func decode(at url: URL) -> PaymentInboxState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PaymentInboxState.self, from: data) else { return PaymentInboxState() }
        return state
    }

    private static func write(_ state: PaymentInboxState, to url: URL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
