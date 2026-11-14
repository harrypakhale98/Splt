import Foundation
import SpltCore

/// What a bank text, email or screenshot said was paid.
struct ParsedPaymentText: Equatable, Sendable {
    var merchant: String?
    var amount: Money
}

/// Reads a payment out of a bank text or receipt email with fixed rules, so it works on every iPhone
/// and gives the same answer every time. It would rather miss a payment than invent one: codes,
/// offers, refunds and bill reminders are skipped, and a payment needs a debit word and an amount.
enum PaymentTextParser {
    static func parse(_ text: String, localCurrency: String = PaymentAmount.localCurrencyCode) -> ParsedPaymentText? {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let lower = flat.lowercased()
        guard !blocked(lower), isDebit(lower),
              let amount = amounts(in: flat, localCurrency: localCurrency).first else { return nil }
        return ParsedPaymentText(merchant: merchant(in: flat), amount: amount)
    }

    // MARK: Filters

    /// Never a purchase: one-time codes, marketing, money coming in and statements.
    private static let blockers = [
        "otp", "one time password", "one-time password", "verification code", "security code", "passcode",
        "do not share", "don't share", "never share", "offer", "pre-approved", "preapproved", "apply now",
        "eligible for", "win ", "reward points", "cashback of", "statement", "is due", "minimum due",
        "due on", "declined", "failed", "unsuccessful", "reversed", "refund"
    ]
    /// Words that say money left: a payment needs one. "Debited from your account and credited to Swiggy" still counts.
    private static let debits = [
        "debited", "spent", "paid", "charged", "purchase", "purchased", "transaction of", "txn of", "used at",
        "withdrawn", "sent", "payment of", "you made"
    ]

    private static func blocked(_ lower: String) -> Bool {
        blockers.contains { lower.contains($0) }
    }

    private static func isDebit(_ lower: String) -> Bool {
        debits.contains { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
    }

    // MARK: Amounts

    private static let symbols: [String: String] = [
        "rs": "INR", "rs.": "INR", "inr": "INR", "₹": "INR", "usd": "USD", "us$": "USD", "$": "$",
        "£": "GBP", "gbp": "GBP", "€": "EUR", "eur": "EUR", "aed": "AED", "sgd": "SGD", "cad": "CAD",
        "aud": "AUD", "¥": "JPY", "jpy": "JPY", "chf": "CHF", "nzd": "NZD"
    ]
    private static let currencyPattern = "rs\\.?|inr|₹|us\\$|usd|\\$|£|gbp|€|eur|aed|sgd|cad|aud|¥|jpy|chf|nzd"
    private static let numberPattern = "[0-9][0-9.,]*[0-9]|[0-9]"
    private static let before = try? NSRegularExpression(
        pattern: "(?i)(\(currencyPattern))\\s?(\(numberPattern))"
    )
    private static let after = try? NSRegularExpression(
        pattern: "(?i)(\(numberPattern))\\s?(inr|usd|gbp|eur|aed|sgd|cad|aud|jpy|chf|nzd|€|£)(?![a-z])"
    )

    /// Every amount with a currency, in the order written.
    static func amounts(in text: String, localCurrency: String = PaymentAmount.localCurrencyCode) -> [Money] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [(Int, Money)] = []
        for (regex, symbolFirst) in [(before, true), (after, false)] {
            for match in regex?.matches(in: text, range: range) ?? [] {
                guard let first = Range(match.range(at: 1), in: text), let second = Range(match.range(at: 2), in: text) else { continue }
                let symbol = String(text[symbolFirst ? first : second]).lowercased()
                let number = String(text[symbolFirst ? second : first])
                guard var code = symbols[symbol], let value = decimal(number) else { continue }
                if code == "$" { code = dollarCountries.contains(localCurrency) ? localCurrency : "USD" }
                if let money = PaymentAmount.money(value, currencyCode: code) { found.append((match.range.location, money)) }
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static let dollarCountries: Set<String> = ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN"]

    /// "1,234.50", "1.234,50", "12,50" and "1,00,000" all read as people mean them.
    static func decimal(_ raw: String) -> Decimal? {
        var number = raw
        let lastComma = number.lastIndex(of: ","), lastDot = number.lastIndex(of: ".")
        if let lastComma, lastDot == nil || lastComma > lastDot!,
           number.distance(from: lastComma, to: number.endIndex) == 3 {
            number = number.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            number = number.replacingOccurrences(of: ",", with: "")
        }
        if number.filter({ $0 == "." }).count > 1 { return nil }
        return Decimal(string: number, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: Merchant

    private static let stopWords = "on|via|using|with|ref|for|avl|bal|card|upi|txn|from|at|thru|through|is|has|was|dated"
    private static let merchantPatterns: [NSRegularExpression] = [
        "\\bto\\s+vpa\\s+([A-Za-z0-9._-]+)@",
        "\\b(?:at|to|towards|info:?)\\s+([A-Za-z][A-Za-z0-9&'*. -]{1,40}?)(?=\\s+(?:\(stopWords))\\b|[.,;:()]|\\s*$)"
    ].compactMap { try? NSRegularExpression(pattern: "(?i)\($0)") }

    static func merchant(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for regex in merchantPatterns {
            for match in regex.matches(in: text, range: range) {
                guard let found = Range(match.range(at: 1), in: text) else { continue }
                let name = String(text[found])
                    .replacingOccurrences(of: "[._*-]+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                let lower = name.lowercased()
                guard name.count >= 2, !lower.hasPrefix("a/c"), !lower.hasPrefix("your"), !lower.hasPrefix("ac "),
                      !lower.hasPrefix("xx"), name.contains(where: \.isLetter) else { continue }
                return name == name.uppercased() ? name.capitalized : name
            }
        }
        return nil
    }
}
