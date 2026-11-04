/// How much text one field keeps. A CloudKit record holds about a megabyte and a record that does not
/// fit can never upload, so a pasted book is cut here, well above anything typed on purpose.
enum RecordLimits {
    static let name = 500
    static let text = 10_000
}

extension String {
    func limited(to characters: Int) -> String {
        // bytes are cheap to count and never fewer than characters
        utf8.count <= characters ? self : String(prefix(characters))
    }
}
