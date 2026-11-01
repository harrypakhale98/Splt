/// Reads and writes comma separated values as RFC 4180 describes: quotes around fields that
/// hold commas, quotes or line breaks, and doubled quotes inside them.
enum CSVText {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldStarted = false
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var index = 0

        func endField() {
            row.append(field)
            field = ""
            fieldStarted = false
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
            } else {
                switch scalar {
                case "\"" where !fieldStarted:
                    inQuotes = true
                    fieldStarted = true
                case ",":
                    endField()
                case "\r":
                    if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                    endRow()
                case "\n":
                    endRow()
                default:
                    field.unicodeScalars.append(scalar)
                    fieldStarted = true
                }
            }
            index += 1
        }
        if fieldStarted || !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Text that a spreadsheet could read as a formula gets a leading apostrophe, so opening an
    /// export never runs something a friend typed into an expense title.
    static func neutralized(_ text: String) -> String {
        guard let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return text }
        return "'" + text
    }

    /// Undoes `neutralized`.
    static func restored(_ text: String) -> String {
        guard text.hasPrefix("'"), let second = text.unicodeScalars.dropFirst().first,
              "=+-@\t\r".unicodeScalars.contains(second) else { return text }
        return String(text.dropFirst())
    }
}
