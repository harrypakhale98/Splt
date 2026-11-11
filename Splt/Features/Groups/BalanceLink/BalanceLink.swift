import Compression
import Foundation

/// Packs a `BalanceSnapshot` into a web link and back.
///
/// The snapshot travels after the `#`, which browsers never send to a server, so the page that
/// reads it is a static file and nothing is uploaded. Compact JSON, then raw deflate, then base64url.
enum BalanceLink {
    /// The static page that reads the link, on the app's GitHub Pages site (`docs/b/`).
    static let pageURL = URL(string: "https://harrypakhale98.github.io/Splt/b/")!

    /// The longest snapshot a link carries, in characters after the `#`. Messaging apps and every
    /// current browser handle far more, but a shorter link is easier to send and to trust.
    static let maxFragmentLength = 6_000

    /// The most a link decodes to, so a crafted one can't ask for a huge buffer.
    static let maxJSONBytes = 256 * 1024

    enum LinkError: Error, Equatable {
        /// Even without its expenses the group doesn't fit in a link.
        case tooLarge
        case malformed
    }

    /// The link for a snapshot. Drops the oldest expenses first when the link would be too long.
    static func url(for snapshot: BalanceSnapshot) throws -> URL {
        var snapshot = snapshot
        while true {
            let fragment = try fragment(for: snapshot)
            if fragment.count <= maxFragmentLength {
                var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)!
                components.fragment = fragment
                guard let url = components.url else { throw LinkError.malformed }
                return url
            }
            guard var expenses = snapshot.expenses, !expenses.isEmpty else { throw LinkError.tooLarge }
            expenses.removeLast()
            snapshot.expenses = expenses
        }
    }

    /// The text after the `#`, whatever its length.
    static func fragment(for snapshot: BalanceSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(snapshot)
        return base64URL(try deflate(json))
    }

    /// Reads a link's fragment back. The app never needs this; it keeps the format honest in tests.
    static func snapshot(fromFragment fragment: String) throws -> BalanceSnapshot {
        guard let packed = data(base64URL: fragment) else { throw LinkError.malformed }
        return try JSONDecoder().decode(BalanceSnapshot.self, from: try inflate(packed))
    }

    // MARK: Deflate

    /// Raw deflate (RFC 1951, no zlib header), which the browser's `DecompressionStream("deflate-raw")` reads.
    static func deflate(_ data: Data) throws -> Data {
        let capacity = data.count + 1_024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    target.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw LinkError.malformed }
        return output.prefix(written)
    }

    static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw LinkError.malformed }
        var output = Data(count: maxJSONBytes)
        let written = output.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    target.bindMemory(to: UInt8.self).baseAddress!, maxJSONBytes,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written < maxJSONBytes else { throw LinkError.malformed }
        return output.prefix(written)
    }

    // MARK: Base64url

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64URL text: String) -> Data? {
        var plain = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        plain += String(repeating: "=", count: (4 - plain.count % 4) % 4)
        return Data(base64Encoded: plain)
    }
}
