import UIKit

/// Draws a `GroupReport` onto US Letter pages with the system fonts.
enum GroupPDFRenderer {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54

    static func data(for report: GroupReport, locale: Locale = .current) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: pdfFormat(title: report.groupName))
        let contentWidth = pageSize.width - margin * 2
        let bottom = pageSize.height - margin

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin
            for row in report.rows(locale: locale) {
                let font = font(for: row.style)
                let lineHeight = ceil(font.lineHeight) + (row.style == .heading ? 6 : 2)
                if row.style == .spacer {
                    y += lineHeight
                    continue
                }
                if y + lineHeight > bottom {
                    context.beginPage()
                    y = margin
                }
                draw(row, font: font, at: y, width: contentWidth)
                y += lineHeight
            }
        }
    }

    private static func draw(_ row: ReportRow, font: UIFont, at y: CGFloat, width: CGFloat) {
        let color: UIColor = row.style == .caption ? .darkGray : .black
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail

        var trailingWidth: CGFloat = 0
        if let trailing = row.trailing {
            let right = NSMutableParagraphStyle()
            right.alignment = .right
            let attributes: [NSAttributedString.Key: Any] = [
                .font: monospaced(font), .foregroundColor: color, .paragraphStyle: right
            ]
            trailingWidth = min(ceil((trailing as NSString).size(withAttributes: attributes).width) + 8, width / 2)
            (trailing as NSString).draw(
                in: CGRect(x: margin + width - trailingWidth, y: y, width: trailingWidth, height: font.lineHeight + 2),
                withAttributes: attributes
            )
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: truncating
        ]
        (row.leading as NSString).draw(
            in: CGRect(x: margin, y: y, width: width - trailingWidth, height: font.lineHeight + 2),
            withAttributes: attributes
        )
    }

    private static func font(for style: ReportRow.Style) -> UIFont {
        switch style {
        case .title: .systemFont(ofSize: 24, weight: .bold)
        case .heading: .systemFont(ofSize: 15, weight: .semibold)
        case .body, .spacer: .systemFont(ofSize: 11)
        case .caption: .systemFont(ofSize: 9)
        }
    }

    private static func monospaced(_ font: UIFont) -> UIFont {
        .monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
    }

    private static func pdfFormat(title: String) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title]
        return format
    }
}
