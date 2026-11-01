import Foundation

/// Text lines that sit at the same height on the page, read left to right.
struct ReceiptRow: Equatable, Sendable {
    var cells: [ReceiptTextLine]

    var text: String {
        cells.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .map { $0.text.tidied }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var midY: CGFloat { cells.map(\.midY).reduce(0, +) / CGFloat(max(cells.count, 1)) }
    var height: CGFloat { cells.map(\.height).max() ?? 0 }
}

enum ReceiptRowBuilder {
    /// Groups recognised lines into rows, top of the page first.
    ///
    /// A receipt prints the name on the left and the price on the right, and the recogniser often
    /// returns them as separate lines. Lines belong to one row when their vertical centres are
    /// closer than about half a text height.
    static func rows(from lines: [ReceiptTextLine]) -> [ReceiptRow] {
        let usable = lines.filter { !$0.text.tidied.isEmpty && $0.boundingBox.height > 0 }
        let ordered = usable.sorted { $0.midY > $1.midY }

        var rows: [ReceiptRow] = []
        for line in ordered {
            if let last = rows.last {
                let tolerance = 0.6 * min(line.height, last.height)
                if abs(line.midY - last.midY) <= tolerance {
                    rows[rows.count - 1].cells.append(line)
                    continue
                }
            }
            rows.append(ReceiptRow(cells: [line]))
        }
        return rows
    }
}
