import Foundation
import SpltCore

/// An invite made for one person who isn't on Splt yet: the group's iCloud invite, and who it is for,
/// so joining takes over that person instead of adding a second one.
///
/// It arrives two ways. The invite page's Join button opens `splt://join?share=<iCloud link>&as=<id>`.
/// Someone who installed Splt first pastes the invite page's own link, which carries the same two
/// things after its `#`.
struct JoinInvite: Hashable, Sendable {
    var shareURL: URL
    var personID: PersonID

    init(shareURL: URL, personID: PersonID) {
        self.shareURL = shareURL
        self.personID = personID
    }

    init?(url: URL) {
        if url.scheme?.lowercased() == DeepLink.scheme {
            guard url.host(percentEncoded: false)?.lowercased() == "join",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let share = items.first(where: { $0.name == "share" })?.value.flatMap(URL.init(string:)),
                  BalanceSnapshot.Join.isShareURL(share),
                  let id = items.first(where: { $0.name == "as" })?.value.flatMap(UUID.init(uuidString:))
            else { return nil }
            self.init(shareURL: share, personID: PersonID(rawValue: id))
            return
        }
        guard Self.isInvitePage(url), let fragment = url.fragment(percentEncoded: false), !fragment.isEmpty,
              let join = (try? BalanceLink.snapshot(fromFragment: fragment))?.join
        else { return nil }
        self.init(shareURL: join.shareURL, personID: PersonID(rawValue: join.personID))
    }

    /// The first invite in pasted text, which is often the whole message with the link at the end.
    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let invite = JoinInvite(url: url) {
            self = invite
            return
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for match in detector.matches(in: trimmed, range: range) {
            if let url = match.url, let invite = JoinInvite(url: url) {
                self = invite
                return
            }
        }
        return nil
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = DeepLink.scheme
        components.host = "join"
        components.queryItems = [
            URLQueryItem(name: "share", value: shareURL.absoluteString),
            URLQueryItem(name: "as", value: personID.rawValue.uuidString)
        ]
        return components.url ?? URL(string: "\(DeepLink.scheme)://join")!
    }

    private static func isInvitePage(_ url: URL) -> Bool {
        let page = BalanceLink.pageURL
        return url.scheme?.lowercased() == "https"
            && url.host()?.lowercased() == page.host()?.lowercased()
            && url.path().hasPrefix(page.path())
    }
}
