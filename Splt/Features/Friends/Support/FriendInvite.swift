import Foundation

/// An invitation to become friends: who is asking, and the id that person has on their device.
/// It travels as a `splt://invite` link, which is also what the QR code holds.
struct FriendInvite: Hashable, Sendable {
    var name: String
    /// The sender's id, so their name lines up with the same person once shared groups sync.
    var personID: UUID?

    init(name: String, personID: UUID? = nil) {
        self.name = name.tidied
        self.personID = personID
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == DeepLink.scheme,
              url.host(percentEncoded: false)?.lowercased() == "invite",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let name = (items.first { $0.name == "name" }?.value ?? "").tidied
        guard !name.isEmpty else { return nil }
        self.name = name
        self.personID = items.first { $0.name == "id" }?.value.flatMap(UUID.init(uuidString:))
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = DeepLink.scheme
        components.host = "invite"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
            + (personID.map { [URLQueryItem(name: "id", value: $0.uuidString)] } ?? [])
        return components.url ?? URL(string: "\(DeepLink.scheme)://invite")!
    }

    /// The text that goes with the link when it is shared.
    var shareMessage: String {
        String(localized: "Let's split costs on Splt. It is free, with no ads. Add me: \(url.absoluteString)")
    }
}
