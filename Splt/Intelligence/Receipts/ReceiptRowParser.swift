import Foundation
import SpltCore

struct ReceiptParsingOptions: Sendable {
    /// Used when no currency symbol or code is printed on the receipt.
    var defaultCurrencyCode = "USD"
    /// Decides whether 03/04/2026 is day first or month first when that cannot be told from the digits.
    var locale = Locale.current
    /// Dates after this are treated as misreads.
    var referenceDate = Date()
}

/// Turns recognised receipt lines into a `ParsedReceipt` using only their text and position.
///
/// Pure and deterministic, so it is tested with fixture lines and needs no camera or Vision.
enum ReceiptRowParser {
    static func parse(lines: [ReceiptTextLine], options: ReceiptParsingOptions = ReceiptParsingOptions()) -> ParsedReceipt {
        parse(pages: [lines], options: options)
    }

    /// Pages are read in order, so a long receipt scanned in several shots reads as one.
    static func parse(pages: [[ReceiptTextLine]], options: ReceiptParsingOptions = ReceiptParsingOptions()) -> ParsedReceipt {
        let rows = pages.flatMap { ReceiptRowBuilder.rows(from: $0) }
        let allText = rows.map(\.text).joined(separator: "\n")
        let currency = CurrencyDetector.printedCodes(in: allText, defaultCode: options.defaultCurrencyCode).first
            ?? options.defaultCurrencyCode.uppercased()
        let digits = MinorUnitParser.fractionDigits(for: currency)

        var reader = BodyReader(currencyCode: currency, fractionDigits: digits)
        for row in rows { reader.consume(row.text) }

        var receipt = reader.receipt()
        receipt.merchant = MerchantReader.merchant(in: rows, fractionDigits: digits)
        receipt.date = ReceiptDateReader.date(in: rows.map(\.text), options: options)
        return receipt
    }
}

// MARK: - Prices

enum ReceiptPrice {
    struct Split {
        var name: String
        var minorUnits: Int64
    }

    private static let currencySymbols = CharacterSet(charactersIn: "$€£¥₹₩₺₱฿₫")
    /// Longer digit runs are misreads, and refusing them keeps the receipt's sums far from overflow.
    static let largestPrice: Int64 = 999_999_999_999

    /// Splits "Burger  12.99 T" into the name and a signed price. Nil when the row ends in no price.
    static func split(_ text: String, fractionDigits: Int) -> Split? {
        var tokens = text.tidied.split(separator: " ").map(String.init)
        guard tokens.count >= 1 else { return nil }

        if tokens.count >= 2, isFlag(tokens[tokens.count - 1]), minorUnits(of: tokens[tokens.count - 2], fractionDigits: fractionDigits) != nil {
            tokens.removeLast()
        }
        while let trailing = tokens.last, tokens.count > 1, isSymbolOnly(trailing) || isCurrencyCode(trailing) {
            tokens.removeLast()
        }
        tokens = joiningSpacedThousands(tokens, fractionDigits: fractionDigits)
        guard let last = tokens.last, let value = minorUnits(of: last, fractionDigits: fractionDigits) else { return nil }
        tokens.removeLast()
        while let trailing = tokens.last, isSymbolOnly(trailing) { tokens.removeLast() }
        return Split(name: tokens.joined(separator: " "), minorUnits: value)
    }

    /// Puts "1 250,00" back together where a space is printed between the thousands.
    /// Only a run that ends in printed decimals is joined. "Ramen 1 250" keeps its digits apart,
    /// because without decimals a small number before the price is more likely a count.
    private static func joiningSpacedThousands(_ tokens: [String], fractionDigits: Int) -> [String] {
        guard fractionDigits > 0, let last = tokens.last,
              TextPattern(#"^\d{3}[.,]\d{\#(fractionDigits)}[$€£¥₹]?$"#).isMatch(in: last) else { return tokens }
        var start = tokens.count - 1
        while start > 0, TextPattern(#"^\d{3}$"#).isMatch(in: tokens[start - 1]) { start -= 1 }
        if start > 0, TextPattern(#"^[$€£¥₹]?[1-9]\d{0,2}$"#).isMatch(in: tokens[start - 1]) {
            start -= 1
        } else {
            // the run has to open with a group that can lead a number
            while start < tokens.count - 1, tokens[start].hasPrefix("0") { start += 1 }
        }
        guard start < tokens.count - 1 else { return tokens }
        return Array(tokens[..<start]) + [tokens[start...].joined()]
    }

    private static func isCurrencyCode(_ token: String) -> Bool {
        (token.count == 3 || token.lowercased() == "zł") && CurrencyDetector.code(forToken: token, defaultCode: "USD") != nil
    }

    /// A single letter or two printed after a price to mark taxed items, such as T or FN.
    private static func isFlag(_ token: String) -> Bool {
        token.count <= 2 && token.allSatisfy { $0.isLetter && $0.isASCII }
    }

    private static func isSymbolOnly(_ token: String) -> Bool {
        token == "R$" || token.unicodeScalars.allSatisfy { currencySymbols.contains($0) || CharacterSet.punctuationCharacters.contains($0) }
    }

    /// Reads one token as a price. Requires the printed decimals so that "12" or "2x" are not prices.
    static func minorUnits(of token: String, fractionDigits: Int) -> Int64? {
        var body = token
        var negative = false
        if body.hasPrefix("(") && body.hasSuffix(")") {
            negative = true
            body = String(body.dropFirst().dropLast())
        }
        for sign in ["-", "\u{2212}", "\u{2013}"] where body.hasPrefix(sign) {
            negative = true
            body = String(body.dropFirst())
        }
        for sign in ["-", "\u{2212}", "\u{2013}", "CR", "cr"] where body.hasSuffix(sign) {
            negative = true
            body = String(body.dropLast(sign.count))
        }
        if body.hasPrefix("R$") { body.removeFirst() }
        body = body.trimmingCharacters(in: currencySymbols)
        for sign in ["-", "\u{2212}", "\u{2013}"] where body.hasPrefix(sign) {
            negative = true
            body = String(body.dropFirst())
        }

        let shape = fractionDigits > 0
            ? #"^\d{1,3}(?:[,.']\d{3})*[.,]\d{\#(fractionDigits)}$|^\d+[.,]\d{\#(fractionDigits)}$"#
            : #"^\d{1,3}(?:[,.']\d{3})+$|^\d{3,}$"#
        guard TextPattern(shape).isMatch(in: body),
              let magnitude = MinorUnitParser.minorUnits(from: body, fractionDigits: fractionDigits),
              magnitude <= largestPrice else { return nil }
        return negative ? -magnitude : magnitude
    }
}

// MARK: - Row meaning

private enum RowKind {
    case subtotal
    case total(priority: Int)
    case tax
    case tip
    case discount
    case payment
    case ignore
    case item
}

private func classify(_ name: String) -> RowKind {
    let words = Set(name.foldedWords)
    let joined = " " + name.foldedWords.joined(separator: " ") + " "

    if !words.isDisjoint(with: ["taxable", "exempt"]) || joined.contains(" tax id ") { return .ignore }
    if words.contains("subtotal") || joined.contains(" sub total ") || joined.contains(" net total ") { return .subtotal }
    let ordered = name.foldedWords
    let taxWords: Set<String> = ["tax", "taxes", "vat", "gst", "hst", "pst", "iva", "sgst", "cgst", "igst"]
    if let taxIndex = ordered.firstIndex(where: taxWords.contains) {
        // "Total excl. VAT" is the amount before tax and "Total inc GST" is the total itself.
        // "Total tax", "Tax total" and "GST included in total" still name the tax.
        let totalIndex = ordered.firstIndex(of: "total")
        if totalIndex != nil, !words.isDisjoint(with: ["ex", "exc", "excl", "excluding", "exclusive", "before", "without"]) {
            return .subtotal
        }
        let saysIncluded = !words.isDisjoint(with: ["inc", "incl", "including", "included", "inclusive", "with", "after"])
        guard let index = totalIndex, index < taxIndex, saysIncluded else { return .tax }
    }
    if !words.isDisjoint(with: ["tip", "gratuity", "gratuities", "svc"])
        || joined.contains(" service charge ") || joined.contains(" service fee ") {
        // A printed table of suggested tips is not a charge. One percentage can be a real
        // service charge, so only a row that lists several is taken for a table.
        let isSuggestion = !words.isDisjoint(with: ["suggested", "suggestion", "suggestions", "recommended"])
            || name.filter { $0 == "%" }.count > 1
        return isSuggestion ? .ignore : .tip
    }
    if !words.isDisjoint(with: ["cash", "change", "tendered", "tender", "visa", "mastercard", "amex", "discover", "debit", "credit", "card", "paid", "payment", "auth", "approval", "approved", "contactless"]) {
        return .payment
    }
    if words.contains("total") || joined.contains(" amount due ") || joined.contains(" balance due ")
        || joined.contains(" amount payable ") || joined.contains(" to pay ") {
        if !words.isDisjoint(with: ["savings", "saved", "items", "item", "qty", "points", "discount", "discounts"]) {
            return .ignore
        }
        let strong = words.contains("grand") || joined.contains(" due ") || joined.contains(" payable ")
        return .total(priority: strong ? 2 : 1)
    }
    if !words.isDisjoint(with: ["discount", "coupon", "promo", "promotion", "savings", "saved", "voucher"]) { return .discount }
    return .item
}

// MARK: - Body

private struct BodyReader {
    let currencyCode: String
    let fractionDigits: Int

    var items: [ReceiptLineItem] = []
    var subtotal: Int64?
    var tax: Int64?
    var tip: Int64?
    var other: Int64?
    var total: Int64?
    var totalPriority = 0
    var sawSummaryRow = false
    var sawTotal = false
    /// Tips printed after the total. They only count once a later total includes them.
    var tipAfterTotal: Int64?
    var closed = false
    var pendingName: String?

    init(currencyCode: String, fractionDigits: Int) {
        self.currencyCode = currencyCode
        self.fractionDigits = fractionDigits
    }

    private func money(_ minor: Int64) -> Money {
        Money(minorUnits: minor, currencyCode: currencyCode)
    }

    mutating func consume(_ text: String) {
        guard !closed else { return }

        if let detail = QuantityDetail(text, fractionDigits: fractionDigits) {
            apply(detail)
            return
        }
        guard let split = ReceiptPrice.split(text, fractionDigits: fractionDigits) else {
            notePendingName(text)
            return
        }

        var name = split.name
        let hasLetters = name.filter(\.isLetter).count >= 2
        if !hasLetters, let pending = pendingName {
            name = pending
        } else if !hasLetters {
            pendingName = nil
            return
        }
        pendingName = nil
        record(name: name, minorUnits: split.minorUnits)
    }

    private mutating func notePendingName(_ text: String) {
        let letters = text.filter(\.isLetter).count
        guard letters >= 3, !["+", "*", "#", "-"].contains(text.first.map(String.init) ?? "") else {
            pendingName = nil
            return
        }
        pendingName = text
    }

    private mutating func record(name rawName: String, minorUnits: Int64) {
        switch classify(rawName) {
        case .ignore, .payment:
            if case .payment = classify(rawName), sawTotal { closed = true }
        case .subtotal:
            if subtotal == nil { subtotal = minorUnits }
            sawSummaryRow = true
        case .tax:
            guard !sawTotal else { return }
            tax = (tax ?? 0) + minorUnits
            sawSummaryRow = true
        case .tip:
            if sawTotal {
                tipAfterTotal = (tipAfterTotal ?? 0) + minorUnits
            } else {
                tip = (tip ?? 0) + minorUnits
            }
            sawSummaryRow = true
        case .total(let priority):
            if let added = tipAfterTotal, let earlier = total, minorUnits == earlier + added {
                tip = (tip ?? 0) + added
                total = minorUnits
                totalPriority = max(totalPriority, priority)
                tipAfterTotal = nil
            } else if !sawTotal || priority > totalPriority {
                total = minorUnits
                totalPriority = priority
            }
            sawTotal = true
            sawSummaryRow = true
        case .discount:
            guard !sawTotal else { return }
            let negative = -abs(minorUnits)
            if sawSummaryRow {
                other = (other ?? 0) + negative
            } else {
                items.append(ReceiptLineItem(name: Self.cleaned(rawName), quantity: 1, unitPrice: nil, total: money(negative)))
            }
        case .item:
            guard !sawTotal else { return }
            if sawSummaryRow {
                other = (other ?? 0) + minorUnits
                return
            }
            let parts = Self.quantity(in: rawName, fractionDigits: fractionDigits)
            let name = Self.cleaned(parts.name)
            guard name.filter(\.isLetter).count >= 2 else { return }
            var unit = parts.unit
            if unit == nil, parts.quantity > 1, minorUnits % Int64(parts.quantity) == 0 {
                unit = minorUnits / Int64(parts.quantity)
            }
            items.append(ReceiptLineItem(
                name: name,
                quantity: parts.quantity,
                unitPrice: unit.map(money),
                total: money(minorUnits)
            ))
        }
    }

    private mutating func apply(_ detail: QuantityDetail) {
        if let pending = pendingName {
            let total = detail.total ?? detail.unit * Int64(detail.quantity)
            pendingName = nil
            record(name: pending, minorUnits: total)
            if var last = items.last, last.name == Self.cleaned(pending), !sawSummaryRow {
                last.quantity = detail.quantity
                last.unitPrice = money(detail.unit)
                items[items.count - 1] = last
            }
        } else if var last = items.last, !sawSummaryRow, detail.quantity > 1,
                  detail.unit * Int64(detail.quantity) == last.total.minorUnits {
            last.quantity = detail.quantity
            last.unitPrice = money(detail.unit)
            items[items.count - 1] = last
        }
    }

    func receipt() -> ParsedReceipt {
        let issues = ReceiptConsistency.issues(
            items: items, subtotal: subtotal, tax: tax, tip: tip, otherCharges: other, total: total
        )
        return ParsedReceipt(
            merchant: nil,
            date: nil,
            currencyCode: currencyCode,
            items: items,
            subtotal: subtotal.map(money),
            tax: tax.map(money),
            tip: tip.map(money),
            otherCharges: other.map(money),
            total: total.map(money),
            issues: issues
        )
    }

    // MARK: Names and quantities

    struct NameParts {
        var name: String
        var quantity: Int
        var unit: Int64?
    }

    /// Reads "2 x Burger", "Burger x2" or "Burger 2 @ 4.50" into a name, quantity and unit price.
    static func quantity(in text: String, fractionDigits: Int) -> NameParts {
        let price = #"[$€£¥₹]?(\d+[.,]\d{\#(fractionDigits)})"#
        if let match = TextPattern(#"^(.+?)\s+(\d{1,2})\s*[@xX×]\s*"# + price + "$").firstMatch(in: text),
           let name = match.group(1, in: text), let count = match.group(2, in: text).flatMap(Int.init),
           let unitText = match.group(3, in: text) {
            return NameParts(name: name, quantity: max(count, 1), unit: MinorUnitParser.minorUnits(from: unitText, fractionDigits: fractionDigits))
        }
        if let match = TextPattern(#"^(\d{1,2})\s*[xX×]\s*(\p{L}.*)$"#).firstMatch(in: text),
           let count = match.group(1, in: text).flatMap(Int.init), let name = match.group(2, in: text) {
            return NameParts(name: name, quantity: max(count, 1), unit: nil)
        }
        if let match = TextPattern(#"^(\d{1,2})\s+(\p{L}.*)$"#).firstMatch(in: text),
           let count = match.group(1, in: text).flatMap(Int.init), let name = match.group(2, in: text) {
            return NameParts(name: name, quantity: max(count, 1), unit: nil)
        }
        if let match = TextPattern(#"^(.+?)\s+[xX×]\s?(\d{1,2})$"#).firstMatch(in: text),
           let name = match.group(1, in: text), let count = match.group(2, in: text).flatMap(Int.init) {
            return NameParts(name: name, quantity: max(count, 1), unit: nil)
        }
        return NameParts(name: text, quantity: 1, unit: nil)
    }

    /// Tidies a printed item name: leader dots, stock codes and stray symbols.
    static func cleaned(_ text: String) -> String {
        var name = text.replacingOccurrences(of: #"\.{2,}"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"^\s*\d{4,}\s+"#, with: "", options: .regularExpression)
        name = name.tidied
        let edge = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces)
        return name.trimmingCharacters(in: edge)
    }
}

/// A row such as "2 x 4.50" or "3 @ 2.00  6.00" that describes the item above it.
private struct QuantityDetail {
    var quantity: Int
    var unit: Int64
    var total: Int64?

    init?(_ text: String, fractionDigits: Int) {
        guard fractionDigits > 0 else { return nil }
        let price = #"[$€£¥₹]?(\d+[.,]\d{\#(fractionDigits)})"#
        let pattern = TextPattern(#"^(\d{1,2})\s*[@xX×]\s*"# + price + #"(?:\s+[$€£¥₹]?(\d+[.,]\d{\#(fractionDigits)}))?(?:\s+[A-Za-z])?$"#)
        guard let match = pattern.firstMatch(in: text),
              let count = match.group(1, in: text).flatMap(Int.init),
              let unitText = match.group(2, in: text),
              let unit = MinorUnitParser.minorUnits(from: unitText, fractionDigits: fractionDigits),
              unit <= ReceiptPrice.largestPrice else { return nil }
        quantity = max(count, 1)
        self.unit = unit
        total = match.group(3, in: text).flatMap { MinorUnitParser.minorUnits(from: $0, fractionDigits: fractionDigits) }
    }
}

// MARK: - Merchant

private enum MerchantReader {
    private static let notAName: Set<String> = [
        "receipt", "invoice", "tel", "telephone", "phone", "fax", "www", "http", "https", "thank", "thanks",
        "welcome", "table", "server", "cashier", "order", "guests", "guest", "customer", "copy", "duplicate",
        "gstin", "tin", "vat", "reg"
    ]

    /// The tallest plain line near the top, which is almost always the shop's name.
    static func merchant(in rows: [ReceiptRow], fractionDigits: Int) -> String? {
        let firstPriced = rows.firstIndex { ReceiptPrice.split($0.text, fractionDigits: fractionDigits) != nil } ?? rows.count
        let header = rows.prefix(min(firstPriced, 6))
        let candidates = header.filter { isPlausible($0.text) }
        guard let best = candidates.enumerated().max(by: { lhs, rhs in
            if lhs.element.height != rhs.element.height { return lhs.element.height < rhs.element.height }
            return lhs.offset > rhs.offset
        })?.element else { return nil }
        return display(best.text)
    }

    private static func isPlausible(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter).count
        let digits = text.filter(\.isNumber).count
        guard letters >= 3, digits <= 2, !text.contains("@") else { return false }
        return Set(text.foldedWords).isDisjoint(with: notAName)
    }

    private static func display(_ text: String) -> String {
        let trimmed = text.tidied.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        guard trimmed == trimmed.uppercased(), trimmed.filter(\.isLetter).count > 3 else { return trimmed }
        return trimmed.lowercased().split(separator: " ").map { String($0).sentenceCased }.joined(separator: " ")
    }
}

// MARK: - Date

enum ReceiptDateReader {
    private static let months = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    /// The first plausible calendar date printed anywhere on the receipt.
    static func date(in rows: [String], options: ReceiptParsingOptions) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = options.locale
        let dayFirst = prefersDayFirst(options.locale)
        for row in rows {
            guard let parts = dateParts(in: row, dayFirst: dayFirst) else { continue }
            var components = DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)
            if let time = timeParts(in: row) {
                components.hour = time.hour
                components.minute = time.minute
            }
            guard let date = calendar.date(from: components),
                  calendar.component(.month, from: date) == parts.month,
                  parts.year >= 2000,
                  date <= options.referenceDate.addingTimeInterval(86_400) else { continue }
            return date
        }
        return nil
    }

    private static func prefersDayFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return false }
        return day < month
    }

    private static func year(_ text: String) -> Int? {
        guard let value = Int(text) else { return nil }
        return text.count <= 2 ? 2000 + value : value
    }

    private static func dateParts(in row: String, dayFirst: Bool) -> (year: Int, month: Int, day: Int)? {
        if let match = TextPattern(#"(?<![\d])(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?![\d])"#).firstMatch(in: row),
           let y = match.group(1, in: row).flatMap(Int.init), let m = match.group(2, in: row).flatMap(Int.init),
           let d = match.group(3, in: row).flatMap(Int.init), (1...12).contains(m), (1...31).contains(d) {
            return (y, m, d)
        }
        if let match = TextPattern(#"(?<![\d])(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})(?![\d])"#).firstMatch(in: row),
           let a = match.group(1, in: row).flatMap(Int.init), let b = match.group(2, in: row).flatMap(Int.init),
           let y = match.group(3, in: row).flatMap(year) {
            let useDayFirst = a > 12 ? true : (b > 12 ? false : dayFirst)
            let (day, month) = useDayFirst ? (a, b) : (b, a)
            if (1...12).contains(month), (1...31).contains(day) { return (y, month, day) }
        }
        let monthNames = months.keys.joined(separator: "|")
        if let match = TextPattern(#"(\d{1,2})(?:st|nd|rd|th)?\s+("# + monthNames + #")[a-z]*\.?,?\s+(\d{4}|\d{2})(?![\d])"#).firstMatch(in: row),
           let d = match.group(1, in: row).flatMap(Int.init),
           let m = match.group(2, in: row).flatMap({ months[$0.lowercased()] }),
           let y = match.group(3, in: row).flatMap(year), (1...31).contains(d) {
            return (y, m, d)
        }
        if let match = TextPattern("(" + monthNames + #")[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4}|\d{2})(?![\d])"#).firstMatch(in: row),
           let m = match.group(1, in: row).flatMap({ months[$0.lowercased()] }),
           let d = match.group(2, in: row).flatMap(Int.init),
           let y = match.group(3, in: row).flatMap(year), (1...31).contains(d) {
            return (y, m, d)
        }
        return nil
    }

    private static func timeParts(in row: String) -> (hour: Int, minute: Int)? {
        guard let match = TextPattern(#"(?<!\d)(\d{1,2}):(\d{2})(?::\d{2})?\s?(am|pm)?"#).firstMatch(in: row),
              var hour = match.group(1, in: row).flatMap(Int.init),
              let minute = match.group(2, in: row).flatMap(Int.init), minute < 60 else { return nil }
        if let meridiem = match.group(3, in: row)?.lowercased() {
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }
        return hour < 24 ? (hour, minute) : nil
    }
}
