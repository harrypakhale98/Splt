import Foundation
import SpltCore

/// What a language model said about a note, as plain strings. Nothing here is trusted yet.
struct QuickAddReading: Equatable, Sendable {
    enum SplitKind: Sendable {
        case unspecified
        case equal
        case adjustments
    }

    struct Adjustment: Equatable, Sendable {
        var name: String
        var amount: String
        var isLess: Bool
    }

    var title = ""
    var amount = ""
    var currency = ""
    var participants: [String] = []
    var payer = ""
    var split: SplitKind = .unspecified
    var adjustments: [Adjustment] = []
}

/// Checks a model's reading against the note it came from.
///
/// The model may choose which number is the price, but it can never invent one: the amount has
/// to be a number that is written in the note, parsed here from text. People must be group
/// members or names written in the note. Anything that fails a check is dropped, and the rule
/// based reading fills the gap.
enum QuickAddValidator {
    static func validate(_ reading: QuickAddReading, text: String, context: QuickAddContext) -> QuickAddDraft {
        let resolver = NameResolver(candidates: context.candidateNames, text: text)
        let words = Set(text.foldedWords)
        var draft = QuickAddDraft()
        draft.source = .model

        let mentioned = CurrencyDetector.codes(in: text, defaultCode: context.defaultCurrencyCode)
        let modelCurrency = reading.currency.trimmingCharacters(in: .whitespaces).uppercased()
        if mentioned.contains(modelCurrency) {
            draft.currencyHint = modelCurrency
        } else {
            draft.currencyHint = mentioned.first
        }
        let code = draft.currencyHint ?? context.defaultCurrencyCode.uppercased()
        let written = writtenAmounts(in: text, currencyCode: code)

        if let minor = amount(reading.amount, currencyCode: code), written.contains(minor) {
            draft.amount = Money(minorUnits: minor, currencyCode: code)
        }

        draft.title = validTitle(reading.title, text: text)

        var seen = Set<String>()
        for typed in reading.participants {
            guard let name = resolver.validatedName(typed, writtenIn: text), seen.insert(name.folded).inserted else { continue }
            draft.participantNames.append(name)
        }

        draft.payer = payer(reading.payer, resolver: resolver, text: text, words: words)
        if let name = draft.payerName, seen.insert(name.folded).inserted {
            draft.participantNames.append(name)
        }

        draft.splitHint = splitHint(reading, resolver: resolver, words: words, code: code, written: written, text: text)
        if case .adjustments(let shares) = draft.splitHint {
            for share in shares where seen.insert(share.name.folded).inserted {
                draft.participantNames.append(share.name)
            }
        }
        return draft
    }

    /// Every number written in the note, in minor units of `currencyCode`.
    /// Plain spaces never join digits, so "table 12 45" is two numbers, not 1245.
    static func writtenAmounts(in text: String, currencyCode: String) -> Set<Int64> {
        var result = Set<Int64>()
        let pattern = TextPattern(#"\d+(?:[.,'\x{00A0}\x{202F}]\d+)*(?<k>k)?"#)
        for match in pattern.matches(in: text) {
            guard let token = match.group(0, in: text) else { continue }
            let isThousands = match.group(named: "k", in: text) != nil
            let digits = isThousands ? String(token.dropLast()) : token
            guard let minor = MinorUnitParser.minorUnits(from: digits, currencyCode: currencyCode) else { continue }
            result.insert(isThousands ? minor * 1000 : minor)
        }
        return result
    }

    private static func amount(_ text: String, currencyCode: String) -> Int64? {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "$€£¥₹ ").union(.letters))
        guard let minor = MinorUnitParser.minorUnits(from: cleaned, currencyCode: currencyCode), minor > 0 else { return nil }
        return minor
    }

    private static func validTitle(_ title: String, text: String) -> String {
        let tidied = title.tidied
        let written = Set(text.foldedWords)
        guard !tidied.isEmpty, tidied.count <= 60, tidied.foldedWords.allSatisfy(written.contains) else { return "" }
        return tidied.sentenceCased
    }

    private static func payer(_ typed: String, resolver: NameResolver, text: String, words: Set<String>) -> QuickAddPayer? {
        let name = typed.tidied
        guard !name.isEmpty else { return nil }
        let payWords: Set<String> = ["paid", "pay", "pays", "covered", "treat", "treated", "got", "fronted", "paying", "spent"]
        guard !words.isDisjoint(with: payWords) else { return nil }
        if NameResolver.refersToWriter(name) {
            return words.isDisjoint(with: ["i", "me", "my", "paid", "spent"]) ? nil : .me
        }
        return resolver.validatedName(name, writtenIn: text).map(QuickAddPayer.person)
    }

    private static func splitHint(
        _ reading: QuickAddReading,
        resolver: NameResolver,
        words: Set<String>,
        code: String,
        written: Set<Int64>,
        text: String
    ) -> QuickAddSplitHint? {
        switch reading.split {
        case .unspecified:
            return nil
        case .equal:
            return words.isDisjoint(with: ["equal", "equally", "even", "evenly", "split", "50"]) ? nil : .equal
        case .adjustments:
            guard !words.isDisjoint(with: ["less", "more", "extra", "fewer", "lower", "higher"]) else { return nil }
            var seen = Set<String>()
            let shares: [QuickAddShare] = reading.adjustments.compactMap { adjustment in
                guard let name = resolver.validatedName(adjustment.name, writtenIn: text),
                      seen.insert(name.folded).inserted,
                      let minor = Self.amount(adjustment.amount, currencyCode: code),
                      written.contains(minor) else { return nil }
                return QuickAddShare(name: name, amount: Money(minorUnits: adjustment.isLess ? -minor : minor, currencyCode: code))
            }
            return shares.isEmpty ? nil : .adjustments(shares)
        }
    }
}
