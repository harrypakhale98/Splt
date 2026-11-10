import CoreText
import UIKit

/// Splits report rows into pages without leaving a heading alone at the bottom of a page or
/// parting a line from the caption under it.
enum ReportLayout {
    struct Placement: Equatable {
        var row: Int
        var y: CGFloat
    }

    /// The rows that must stay on one page, in order. A heading or a table's column labels join the
    /// row after them, and captions and a table's total join the row before them.
    static func blocks(_ rows: [ReportRow]) -> [[Int]] {
        var blocks: [[Int]] = []
        var lead: [Int] = []
        for (index, row) in rows.enumerated() {
            switch row.style {
            case .title, .heading, .columns:
                lead.append(index)
            case .spacer where lead.isEmpty:
                blocks.append([index])
            case .spacer:
                lead.append(index)
            case .caption, .tableTotal:
                if lead.isEmpty, let last = blocks.indices.last, rows[blocks[last][0]].style != .spacer {
                    blocks[last].append(index)
                } else {
                    blocks.append(lead + [index])
                    lead = []
                }
            default:
                blocks.append(lead + [index])
                lead = []
            }
        }
        if !lead.isEmpty { blocks.append(lead) }
        return blocks
    }

    /// Each page's rows with their offsets from the top of the text area. Spacers at the top of a
    /// page are dropped. A block taller than a whole page breaks between its rows.
    static func pages(_ rows: [ReportRow], available: CGFloat, height: (ReportRow) -> CGFloat) -> [[Placement]] {
        var pages: [[Placement]] = [[]]
        var y: CGFloat = 0
        func newPage() {
            pages.append([])
            y = 0
        }
        for block in blocks(rows) {
            if block.count == 1, rows[block[0]].style == .spacer {
                if !pages[pages.count - 1].isEmpty { y += height(rows[block[0]]) }
                continue
            }
            let blockHeight = block.reduce(0) { $0 + height(rows[$1]) }
            if y + blockHeight > available, !pages[pages.count - 1].isEmpty { newPage() }
            for index in block {
                let rowHeight = height(rows[index])
                if y + rowHeight > available, !pages[pages.count - 1].isEmpty { newPage() }
                pages[pages.count - 1].append(Placement(row: index, y: y))
                y += rowHeight
            }
        }
        return pages
    }
}

/// Draws a `GroupReport` as Splt on paper: a white page, the group's name and every figure in the
/// serif face, the rest in the system font, and hairlines between sections.
enum GroupPDFRenderer {
    static let a4 = CGSize(width: 595, height: 842)
    static let letter = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54
    /// Room under the text for the running footer.
    private static let footerSpace: CGFloat = 22

    /// Regions where US Letter is the usual paper. Everywhere else gets A4.
    private static let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "PR"]

    static func paperSize(for locale: Locale) -> CGSize {
        guard let region = locale.region?.identifier else { return a4 }
        return letterRegions.contains(region.uppercased()) ? letter : a4
    }

    static func data(for report: GroupReport, locale: Locale = .current) -> Data {
        let pageSize = paperSize(for: locale)
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: pdfFormat(title: report.groupName))
        let width = pageSize.width - margin * 2
        let available = pageSize.height - margin * 2 - footerSpace
        let rows = report.rows(locale: locale)
        let pages = ReportLayout.pages(rows, available: available, height: height(of:))
        let columns = columnWidth(for: rows, width: width)

        return renderer.pdfData { context in
            for (number, page) in pages.enumerated() {
                context.beginPage()
                for placement in page {
                    draw(rows[placement.row], at: margin + placement.y, width: width, columnWidth: columns)
                }
                let footer = String(localized: "\(report.groupName) · page \(number + 1) of \(pages.count)")
                drawText(
                    footer, font: Print.caption, color: Print.secondary,
                    in: CGRect(x: margin, y: pageSize.height - margin, width: width, height: ceil(Print.caption.lineHeight) + 2),
                    alignment: .center
                )
            }
        }
    }

    // MARK: Layout

    static func height(of row: ReportRow) -> CGFloat {
        switch row.style {
        case .title: ceil(Print.title.lineHeight) + 4
        case .heading: Print.headingRuleGap + ceil(Print.heading.lineHeight) + 4
        case .spacer: 12
        case .caption: ceil(Print.caption.lineHeight) + 3
        case .columns: ceil(Print.caption.lineHeight) + 3
        case .body, .tableRow: ceil(Print.body.lineHeight) + 3
        case .tableTotal: 4 + ceil(Print.body.lineHeight) + 3
        }
    }

    /// One width for every figure column, wide enough for the widest figure, within reason.
    private static func columnWidth(for rows: [ReportRow], width: CGFloat) -> CGFloat {
        let widest = rows.flatMap(\.columns).map { ceil(($0 as NSString).size(withAttributes: [.font: Print.figure]).width) }
            .max() ?? 0
        let count = CGFloat(rows.map(\.columns.count).max() ?? 1)
        let cap = (width * 0.7) / max(count, 1)
        return min(max(widest + 12, 64), cap)
    }

    // MARK: Drawing

    private static func draw(_ row: ReportRow, at y: CGFloat, width: CGFloat, columnWidth: CGFloat) {
        let lineHeight = height(of: row)
        switch row.style {
        case .spacer:
            return
        case .title:
            drawText(row.leading, font: Print.title, color: Print.text, in: CGRect(x: margin, y: y, width: width, height: lineHeight))
        case .heading:
            rule(at: y, width: width)
            drawText(
                row.leading, font: Print.heading, color: Print.secondary,
                in: CGRect(x: margin, y: y + Print.headingRuleGap, width: width, height: lineHeight - Print.headingRuleGap)
            )
        case .caption:
            drawText(row.leading, font: Print.caption, color: Print.secondary, in: CGRect(x: margin, y: y, width: width, height: lineHeight))
        case .body:
            var trailingWidth: CGFloat = 0
            if let trailing = row.trailing {
                trailingWidth = min(ceil((trailing as NSString).size(withAttributes: [.font: Print.figure]).width) + 8, width / 2)
                drawText(
                    trailing, font: Print.figure, color: Print.text,
                    in: CGRect(x: margin + width - trailingWidth, y: y, width: trailingWidth, height: lineHeight), alignment: .right
                )
            }
            drawText(
                row.leading, font: Print.body, color: Print.text,
                in: CGRect(x: margin, y: y, width: width - trailingWidth, height: lineHeight)
            )
        case .columns, .tableRow, .tableTotal:
            var top = y
            if row.style == .tableTotal {
                rule(at: y + 1, width: width)
                top += 4
            }
            let isLabels = row.style == .columns
            let figureFont = isLabels ? Print.caption : Print.figure
            let color = isLabels ? Print.secondary : Print.text
            let nameWidth = width - columnWidth * CGFloat(row.columns.count)
            drawText(
                row.leading, font: isLabels ? Print.caption : Print.body, color: isLabels ? Print.secondary : Print.text,
                in: CGRect(x: margin, y: top, width: nameWidth - 6, height: lineHeight)
            )
            for (index, text) in row.columns.enumerated() {
                let x = margin + nameWidth + columnWidth * CGFloat(index)
                drawText(text, font: figureFont, color: color, in: CGRect(x: x, y: top, width: columnWidth, height: lineHeight), alignment: .right)
            }
        }
    }

    /// One line of text, shrunk a little before it is cut short, like `minimumScaleFactor`.
    private static func drawText(
        _ text: String, font: UIFont, color: UIColor, in rect: CGRect, alignment: NSTextAlignment = .natural
    ) {
        guard !text.isEmpty, rect.width > 0 else { return }
        var fitted = font
        let natural = (text as NSString).size(withAttributes: [.font: font]).width
        if natural > rect.width {
            fitted = font.withSize(max(font.pointSize * 0.75, font.pointSize * rect.width / natural))
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [.font: fitted, .foregroundColor: color, .paragraphStyle: style]
        let offset = max(0, (font.lineHeight - fitted.lineHeight) / 2)
        (text as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: max(rect.height, fitted.lineHeight)),
            withAttributes: attributes
        )
    }

    private static func rule(at y: CGFloat, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y + 0.25))
        path.addLine(to: CGPoint(x: margin + width, y: y + 0.25))
        path.lineWidth = 0.5
        Print.hairline.setStroke()
        path.stroke()
    }

    private static func pdfFormat(title: String) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title]
        return format
    }

    /// The app's type and the light values of its ink, fixed for paper.
    private enum Print {
        static var title: UIFont { serif(size: 24) }
        static var figure: UIFont { serif(size: 10.5, tabular: true) }
        static var body: UIFont { UIFont.systemFont(ofSize: 10.5, weight: .regular) }
        static var heading: UIFont { UIFont.systemFont(ofSize: 9, weight: .regular) }
        static var caption: UIFont { UIFont.systemFont(ofSize: 8.5, weight: .regular) }
        /// Space between a section's hairline and its label.
        static let headingRuleGap: CGFloat = 7

        /// `Ink.text`, `Ink.secondary` and `Ink.hairline` in light mode.
        static var text: UIColor { color(0x1A1917) }
        static var secondary: UIColor { color(0x66635B) }
        static var hairline: UIColor { color(0xE2DED5) }

        private static func serif(size: CGFloat, tabular: Bool = false) -> UIFont {
            var descriptor = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor
            descriptor = descriptor.withDesign(.serif) ?? descriptor
            if tabular {
                descriptor = descriptor.addingAttributes([
                    .featureSettings: [[
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
                    ]]
                ])
            }
            return UIFont(descriptor: descriptor, size: size)
        }

        private static func color(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}
