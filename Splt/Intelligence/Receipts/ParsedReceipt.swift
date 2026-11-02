import Foundation
import SpltCore

/// A line of text found on a receipt photo, with where it sits.
struct ReceiptTextLine: Equatable, Sendable {
    var text: String
    /// Normalised to the page, origin at the bottom left, the way Vision reports it.
    var boundingBox: CGRect
    var confidence: Float = 1

    var midY: CGFloat { boundingBox.midY }
    var height: CGFloat { boundingBox.height }
}

struct ReceiptLineItem: Equatable, Sendable {
    var name: String
    var quantity: Int
    /// The price of one unit when the receipt prints it.
    var unitPrice: Money?
    /// What the receipt charges for the whole line. Negative for discounts.
    var total: Money
}

/// A reason the numbers on a receipt do not add up. Shown as a gentle hint to review the scan.
enum ReceiptIssue: Equatable, Sendable {
    case noItems
    case missingTotal
    /// Items add up to more (positive) or less (negative) than the printed subtotal, in minor units.
    case itemsDifferFromSubtotal(difference: Int64)
    /// The printed total is more (positive) or less (negative) than its parts, in minor units.
    case totalDiffersFromParts(difference: Int64)
}

/// Everything read from a receipt. Any field may be missing when it could not be read.
struct ParsedReceipt: Equatable, Sendable {
    var merchant: String?
    var date: Date?
    var currencyCode: String
    var items: [ReceiptLineItem] = []
    var subtotal: Money?
    var tax: Money?
    var tip: Money?
    /// Service fees, delivery fees and discounts printed between the subtotal and the total.
    var otherCharges: Money?
    var total: Money?
    var issues: [ReceiptIssue] = []

    var isConsistent: Bool { issues.isEmpty }
}

enum ReceiptConsistency {
    /// Checks that items, tax, tip and other charges add up to the total, and that items match the subtotal.
    static func issues(
        items: [ReceiptLineItem],
        subtotal: Int64?,
        tax: Int64?,
        tip: Int64?,
        otherCharges: Int64?,
        total: Int64?
    ) -> [ReceiptIssue] {
        var found: [ReceiptIssue] = []
        if items.isEmpty { found.append(.noItems) }
        guard let total else { return found + [.missingTotal] }

        let itemsSum = items.reduce(Int64(0)) { $0 + $1.total.minorUnits }
        if let subtotal, !items.isEmpty, itemsSum != subtotal {
            found.append(.itemsDifferFromSubtotal(difference: itemsSum - subtotal))
        }
        let base = subtotal ?? itemsSum
        guard subtotal != nil || !items.isEmpty else { return found }
        let expected = base + (tax ?? 0) + (tip ?? 0) + (otherCharges ?? 0)
        if expected != total {
            found.append(.totalDiffersFromParts(difference: total - expected))
        }
        return found
    }
}
