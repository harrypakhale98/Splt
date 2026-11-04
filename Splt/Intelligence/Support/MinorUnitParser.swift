import Foundation
import SpltCore

/// Turns typed or recognised amounts such as "1,234.50" or "12,5" into integer minor units.
///
/// Money never passes through Double or Decimal here: the digits are read as text and scaled
/// by the currency's number of fraction digits.
enum MinorUnitParser {
    /// Number of digits after the decimal point for an ISO 4217 code (2 for USD, 0 for JPY).
    static func fractionDigits(for currencyCode: String) -> Int {
        Currency.minorUnitExponent(for: currencyCode)
    }

    static func minorUnits(from text: String, currencyCode: String) -> Int64? {
        minorUnits(from: text, fractionDigits: fractionDigits(for: currencyCode))
    }

    /// Reads a non-negative amount. Returns nil for anything that is not clearly a number.
    static func minorUnits(from text: String, fractionDigits: Int) -> Int64? {
        let allowedGroupMarks: Set<Character> = ["'", "\u{2019}", "\u{00A0}", "\u{202F}"]
        var cleaned = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character.isASCII, character.isNumber || character == "." || character == "," {
                cleaned.append(character)
            } else if allowedGroupMarks.contains(character) {
                continue
            } else {
                return nil
            }
        }
        guard cleaned.contains(where: \.isNumber) else { return nil }

        let (integerDigits, fractionPart) = split(cleaned, fractionDigits: fractionDigits) ?? ("", nil)
        guard !integerDigits.isEmpty || fractionPart != nil else { return nil }
        return compose(integerDigits: integerDigits, fractionPart: fractionPart ?? "", fractionDigits: fractionDigits)
    }

    private static func split(_ text: String, fractionDigits: Int) -> (String, String?)? {
        let separators = text.enumerated().filter { $0.element == "." || $0.element == "," }
        guard let last = separators.last else { return (text, nil) }

        let kinds = Set(separators.map(\.element))
        var decimalIndex: Int?

        if kinds.count == 2 {
            decimalIndex = last.offset
        } else if separators.count == 1 {
            let digitsAfter = text.count - last.offset - 1
            let isDot = last.element == "."
            if digitsAfter == 0 {
                decimalIndex = last.offset
            } else if fractionDigits == 0 {
                guard digitsAfter == 3, text.first != "0" else { return nil }
            } else if digitsAfter == 3 && !(fractionDigits == 3 && isDot) {
                guard text.first != "0" else { return nil }
                decimalIndex = nil
            } else if digitsAfter <= fractionDigits {
                decimalIndex = last.offset
            } else {
                return nil
            }
        } else {
            let groups = text.split(separator: last.element, omittingEmptySubsequences: false).dropFirst()
            // the last group has three digits, the ones before two or three: 1,234,567 or 1,23,456
            guard groups.last?.count == 3, groups.dropLast().allSatisfy({ (2...3).contains($0.count) }) else { return nil }
        }

        if let decimalIndex {
            let characters = Array(text)
            let integerPart = String(characters[..<decimalIndex]).filter(\.isNumber)
            let fraction = String(characters[(decimalIndex + 1)...]).filter(\.isNumber)
            guard fraction.count <= fractionDigits else { return nil }
            return (integerPart, fraction)
        }
        return (text.filter(\.isNumber), nil)
    }

    private static func compose(integerDigits: String, fractionPart: String, fractionDigits: Int) -> Int64? {
        let paddedFraction = fractionPart.padding(toLength: fractionDigits, withPad: "0", startingAt: 0)
        let digits = integerDigits + paddedFraction
        guard !digits.isEmpty, digits.count <= 17 else { return nil }
        guard let value = Int64(digits), value <= MoneyParser.maximumMinorUnits else { return nil }
        return value
    }
}
