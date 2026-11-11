import Foundation
import SpltCore

/// An invite to a group: the group's iCloud invite and, for an invite made for one person who isn't on
/// Splt yet, who that is and their name, so joining takes over that person instead of adding a second one.
/// An invite for the whole group chat has no person: whoever opens it picks themselves.
///
/// It arrives two ways. The invite page's Join button opens
/// `splt://join?share=<iCloud link>&as=<id>&name=<name>`, with `as` and `name` only for one person.
/// Someone who installed Splt first pastes the invite page's own link, which carries the same after its `#`.
struct JoinInvite: Hashable, Sendable {
    var shareURL: URL
    /// Who the invite was made for, or nil when the person joining picks themselves.
    var personID: PersonID?
    /// The name the group knows that person by, which someone who never chose a name takes.
    var name: String?

    init(shareURL: URL, personID: PersonID?, name: String? = nil) {
        self.shareURL = shareURL
        self.personID = personID
        self.name = name.flatMap { Self.tidy($0) }
    }

    init?(url: URL) {
        if url.scheme?.lowercased() == DeepLink.scheme {
            guard url.host(percentEncoded: false)?.lowercased() == "join",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let share = items.first(where: { $0.name == "share" })?.value.flatMap(URL.init(string:)),
                  BalanceSnapshot.Join.isShareURL(share)
            else { return nil }
            let person = items.first(where: { $0.name == "as" })?.value
            let id = person.flatMap(UUID.init(uuidString:))
            // a person that doesn't read as an id is a broken link, not an invite for anyone
            guard person == nil || id != nil else { return nil }
            self.init(
                shareURL: share, personID: id.map(PersonID.init(rawValue:)),
                name: id == nil ? nil : items.first(where: { $0.name == "name" })?.value
            )
            return
        }
        guard Self.isInvitePage(url), let fragment = url.fragment(percentEncoded: false), !fragment.isEmpty,
              let snapshot = try? BalanceLink.snapshot(fromFragment: fragment)
        else { return nil }
        if let join = snapshot.join {
            self.init(
                shareURL: join.shareURL, personID: PersonID(rawValue: join.personID),
                name: snapshot.members[join.person].name
            )
        } else if let group = snapshot.groupJoin {
            self.init(shareURL: group.shareURL, personID: nil)
        } else {
            return nil
        }
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
        var items = [URLQueryItem(name: "share", value: shareURL.absoluteString)]
        if let personID {
            items.append(URLQueryItem(name: "as", value: personID.rawValue.uuidString))
            if let name { items.append(URLQueryItem(name: "name", value: name)) }
        }
        components.queryItems = items
        return components.url ?? URL(string: "\(DeepLink.scheme)://join")!
    }

    /// Who sync should claim once the group arrives.
    var joinAs: JoinAs {
        personID.map(JoinAs.person) ?? .askWho
    }

    private static func tidy(_ name: String) -> String? {
        let flat = name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return nil }
        return String(flat.prefix(BalanceSnapshot.nameLimit))
    }

    private static func isInvitePage(_ url: URL) -> Bool {
        let page = BalanceLink.pageURL
        return url.scheme?.lowercased() == "https"
            && url.host()?.lowercased() == page.host()?.lowercased()
            && url.path().hasPrefix(page.path())
    }
}
