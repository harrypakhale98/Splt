import Foundation
import SpltCore

/// Reads a note with plain rules: regular expressions for amounts and phrases, and the
/// NaturalLanguage tagger for names. Works everywhere, needs no model, and gives the same
/// answer every time.
///
/// It works in passes. Each pass finds one kind of phrase, records it and blanks it out of the
/// working text, so what is left at the end is the title.
struct RuleBasedQuickAddParser: QuickAddParsing {
    var categories = KeywordCategorySuggester()

    func parse(_ text: String, context: QuickAddContext) async -> QuickAddDraft {
        parseNow(text, context: context)
    }

    func parseNow(_ rawText: String, context: QuickAddContext) -> QuickAddDraft {
        let original = NumberWords.replacingSpelledNumbers(in: rawText.tidied)
        guard !original.isEmpty else { return QuickAddDraft() }

        var pass = Pass(text: original, resolver: NameResolver(candidates: context.candidateNames, text: original))
        pass.takeAdjustments()
        pass.takeExactShares()
        pass.takePayer()
        let explicitEqual = pass.takeEqualSplit()
        pass.takeParticipants()

        let currencyMentions = CurrencyDetector.codes(in: original, defaultCode: context.defaultCurrencyCode)
        let amount = pass.takeAmount(defaultCode: currencyMentions.first ?? context.defaultCurrencyCode)

        var draft = QuickAddDraft()
        draft.currencyHint = amount?.explicitCode ?? currencyMentions.first
        let code = draft.currencyHint ?? context.defaultCurrencyCode.uppercased()
        if let amount {
            draft.amount = Money(minorUnits: amount.minorUnits, currencyCode: amount.explicitCode ?? code)
        }
        draft.title = pass.title()
        draft.participantNames = pass.participants
        draft.payer = pass.payer
        draft.splitHint = splitHint(pass: pass, explicitEqual: explicitEqual, code: code)
        draft.category = categories.suggestNow(title: draft.title, merchant: nil)?.category
        return draft
    }

    private func splitHint(pass: Pass, explicitEqual: Bool, code: String) -> QuickAddSplitHint? {
        func shares(_ entries: [Pass.Entry]) -> [QuickAddShare] {
            entries.compactMap { entry in
                guard let minor = MinorUnitParser.minorUnits(from: entry.amountText, currencyCode: code) else { return nil }
                return QuickAddShare(name: entry.name, amount: Money(minorUnits: entry.sign * minor, currencyCode: code))
            }
        }
        let exact = shares(pass.exactShares)
        if !exact.isEmpty { return .exactAmounts(exact) }
        let adjustments = shares(pass.adjustments)
        if !adjustments.isEmpty { return .adjustments(adjustments) }
        return explicitEqual ? .equal : nil
    }
}

// MARK: - Passes

private struct Pass {
    struct Entry {
        var name: String
        var amountText: String
        var sign: Int64
    }

    struct FoundAmount {
        var minorUnits: Int64
        var explicitCode: String?
    }

    /// Stands in for removed phrases so words on either side never glue together.
    static let gap = " \u{00A6} "

    var text: String
    let resolver: NameResolver
    var participants: [String] = []
    var payer: QuickAddPayer?
    var adjustments: [Entry] = []
    var exactShares: [Entry] = []

    init(text: String, resolver: NameResolver) {
        self.text = text
        self.resolver = resolver
    }

    private static let adjustmentPatterns: [TextPattern] = [
        TextPattern(#"(?<name>NAME)\s+(?:owes?|pays?|will\s+pay|should\s+pay)\s+(?<amt>AMT)\s*(?:dollars?|bucks|euros?|pounds?)?\s+(?<dir>less|more|extra|fewer|lower|higher)\b"#
            .replacingPlaceholders()),
        TextPattern(#"(?<amt>AMT)\s*(?:dollars?|bucks|euros?|pounds?)?\s+(?<dir>less|more|extra)\s+(?:for|from|on)\s+(?<name>NAME)"#
            .replacingPlaceholders()),
        TextPattern(#"(?<name>NAME)(?:'s|’s)?\s+(?:share|part|portion)\s+(?:is\s+)?(?<amt>AMT)\s*(?:dollars?|bucks|euros?|pounds?)?\s+(?<dir>less|more)\b"#
            .replacingPlaceholders())
    ]

    private static let exactPatterns: [TextPattern] = [
        TextPattern(#"(?<name>NAME)\s+(?:owes?|will\s+owe)\s+(?<amt>AMT)"#.replacingPlaceholders()),
        TextPattern(#"(?<name>NAME)(?:'s|’s)\s+share\s+(?:is\s+)?(?<amt>AMT)"#.replacingPlaceholders())
    ]

    private static let meVerbs = #"(?:paid|pay|covered|cover|treated|got\s+(?:it|this|that|the\s+(?:bill|check|tab))|am\s+paying|will\s+pay|picked\s+up\s+the\s+(?:bill|check|tab))"#
    private static let mePatterns: [TextPattern] = [
        TextPattern(#"\b(?:i|i'll|i’ll)\s+(?:both\s+)?"#.appending(meVerbs).appending(#"\b"#)),
        TextPattern(#"\bpaid\s+by\s+me\b|\bmy\s+treat\b|\bon\s+me\b"#),
        TextPattern(#"^\s*(?:i\s+)?(?:paid|spent)\b"#)
    ]
    private static let paidByPattern = TextPattern(#"\bpaid\s+by\s+(?<name>NAME)"#.replacingPlaceholders())
    private static let namedPayerPattern = TextPattern(
        #"(?:(?<first>NAME)\s+)?(?<name>NAME)\s+(?:paid|covered|treated|fronted|is\s+paying|got\s+(?:it|this|that|the\s+(?:bill|check|tab))|picked\s+up\s+the\s+(?:bill|check|tab))\b"#
            .replacingPlaceholders()
    )
    private static let equalPattern = TextPattern(
        #"\b(?:(?:split\s+(?:it\s+|this\s+|the\s+bill\s+)?)?(?:equally|evenly)|(?:equal|even)\s+split|50\s*[/-]\s*50|split\s+(?:it\s+)?(?:equal|even))\b"#
    )
    private static let markerPattern = TextPattern(#"(?<![\p{L}])(?:with|w/|between|among)\s+"#)
    private static let tokenPattern = TextPattern(#"\p{L}[\p{L}\p{M}'’-]*|[,&+]|\S"#)

    // MARK: Splitting the cost

    mutating func takeAdjustments() {
        for pattern in Self.adjustmentPatterns {
            while let match = pattern.firstMatch(in: text) {
                let direction = (match.group(named: "dir", in: text) ?? "").lowercased()
                let sign: Int64 = ["less", "fewer", "lower"].contains(direction) ? -1 : 1
                record(match, into: \.adjustments, sign: sign)
            }
        }
    }

    mutating func takeExactShares() {
        for pattern in Self.exactPatterns {
            while let match = pattern.firstMatch(in: text) {
                record(match, into: \.exactShares, sign: 1)
            }
        }
    }

    private mutating func record(_ match: NSTextCheckingResult, into keyPath: WritableKeyPath<Pass, [Entry]>, sign: Int64) {
        let typedName = match.group(named: "name", in: text) ?? ""
        let amountText = (match.group(named: "amt", in: text) ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "$€£¥₹ "))
        blank(match.range)
        guard !NameResolver.refersToWriter(typedName), let name = resolver.plausibleName(typedName) ?? lenientName(typedName) else {
            return
        }
        self[keyPath: keyPath].append(Entry(name: name, amountText: amountText, sign: sign))
        addParticipant(name)
    }

    /// Names right before "owes" are clearly people even when lowercase, unless they are plain words.
    private func lenientName(_ word: String) -> String? {
        guard !NameResolver.isStopWord(word), !KeywordCategoryTable.standard.recognises(word: word) else { return nil }
        return resolver.matchingCandidate(for: word) ?? (word.count >= 2 ? word.sentenceCased : nil)
    }

    mutating func takeEqualSplit() -> Bool {
        var found = false
        while let match = Self.equalPattern.firstMatch(in: text) {
            blank(match.range)
            found = true
        }
        return found
    }

    // MARK: Who paid

    mutating func takePayer() {
        for pattern in Self.mePatterns {
            if let match = pattern.firstMatch(in: text) {
                blank(match.range)
                payer = .me
                return
            }
        }
        for pattern in [Self.paidByPattern, Self.namedPayerPattern] {
            for match in pattern.matches(in: text) {
                let typed = match.group(named: "name", in: text) ?? ""
                guard !NameResolver.refersToWriter(typed), let last = resolver.plausibleName(typed),
                      let nameRange = Range(match.range(withName: "name"), in: text),
                      let wholeRange = Range(match.range, in: text) else { continue }
                var name = last
                var start = nameRange.lowerBound
                if let first = match.group(named: "first", in: text),
                   let full = resolver.fullName(first, typed),
                   let firstRange = Range(match.range(withName: "first"), in: text) {
                    name = full
                    start = firstRange.lowerBound
                }
                text.replaceSubrange(start..<wholeRange.upperBound, with: Self.gap)
                payer = .person(name)
                addParticipant(name)
                return
            }
        }
    }

    // MARK: Who shared it

    mutating func takeParticipants() {
        var progressed = true
        while progressed {
            progressed = false
            for marker in Self.markerPattern.matches(in: text) {
                guard let markerRange = Range(marker.range, in: text) else { continue }
                let (names, end) = readNames(from: markerRange.upperBound)
                guard end > markerRange.upperBound else { continue }
                names.forEach { addParticipant($0) }
                text.replaceSubrange(markerRange.lowerBound..<end, with: Self.gap)
                progressed = true
                break
            }
        }
    }

    /// Reads "Sam, Priya and me" and stops at the first word that is not a name or a joiner.
    /// Returns the names found and where the list ends.
    private func readNames(from start: String.Index) -> (names: [String], end: String.Index) {
        let tokens = Self.tokenPattern.matches(in: text).compactMap { match -> (word: String, range: Range<String.Index>)? in
            guard let range = Range(match.range, in: text), range.lowerBound >= start else { return nil }
            return (String(text[range]), range)
        }

        var names: [String] = []
        var end = start
        var expectingName = true
        var index = 0
        while index < tokens.count {
            let (word, range) = tokens[index]
            if expectingName {
                if ["me", "myself"].contains(word.folded) {
                    end = range.upperBound
                } else if index + 1 < tokens.count, tokens[index + 1].word.first?.isLetter == true,
                          let full = resolver.matchingCandidate(for: word + " " + tokens[index + 1].word) {
                    names.append(full)
                    end = tokens[index + 1].range.upperBound
                    index += 1
                } else if let name = resolver.plausibleName(word) {
                    var full = name
                    end = range.upperBound
                    if index + 1 < tokens.count, let surname = resolver.fullName(word, tokens[index + 1].word),
                       resolver.matchingCandidate(for: word) == nil,
                       index + 2 >= tokens.count || !resolver.looksLikeName(tokens[index + 2].word) {
                        full = surname
                        end = tokens[index + 1].range.upperBound
                        index += 1
                    }
                    names.append(full)
                } else {
                    break
                }
                expectingName = false
            } else {
                guard ["and", ",", "&", "+", "plus", "n"].contains(word.lowercased()) else { break }
                expectingName = true
            }
            index += 1
        }
        return (names, end)
    }

    private mutating func addParticipant(_ name: String) {
        if !participants.contains(where: { $0.folded == name.folded }) {
            participants.append(name)
        }
    }

    // MARK: Amount

    private static let amountPattern: TextPattern = {
        let words = CurrencyDetector.wordAlternation
        return TextPattern(
            #"(?<![\p{L}\d.,:/#])(?:(?<pre>"# + words + #")\.?\s?)?(?:(?<sym>[$€£¥₹])\s?)?"#
                + #"(?<num>\d{1,3}(?:[,'.]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?<k>k(?![\p{L}]))?(?![\d:/%]|[.,]\d)"#
                + #"(?:\s?(?<word>"# + words + #")(?![\p{L}]))?"#
        )
    }()

    private static let notMoneyAfter: Set<String> = [
        "people", "person", "persons", "ppl", "friends", "guests", "pax", "items", "item", "days", "day",
        "nights", "night", "hours", "hrs", "hr", "mins", "min", "minutes", "kids", "adults", "x", "am",
        "pm", "st", "nd", "rd", "th", "km", "kg", "miles", "percent", "of"
    ]
    private static let notMoneyBefore: Set<String> = [
        "table", "room", "seat", "no", "number", "order", "flight", "gate", "route", "bus"
    ]

    mutating func takeAmount(defaultCode: String) -> FoundAmount? {
        struct Candidate {
            var range: NSRange
            var found: FoundAmount
            var hasCurrency: Bool
        }
        var candidates: [Candidate] = []
        for match in Self.amountPattern.matches(in: text) {
            guard let whole = Range(match.range, in: text) else { continue }
            let following = text[whole.upperBound...].drop { $0 == " " }
            let nextWord = String(following.prefix { $0.isLetter }).lowercased()
            if Self.notMoneyAfter.contains(nextWord), match.group(named: "word", in: text) == nil { continue }
            let preceding = text[..<whole.lowerBound].reversed().drop { $0 == " " }
            let previousWord = String(preceding.prefix { $0.isLetter }.reversed()).lowercased()
            let hasMarker = match.group(named: "sym", in: text) != nil || match.group(named: "pre", in: text) != nil
                || match.group(named: "word", in: text) != nil
            if Self.notMoneyBefore.contains(previousWord), !hasMarker { continue }

            let marker = match.group(named: "sym", in: text)
                ?? match.group(named: "pre", in: text)
                ?? match.group(named: "word", in: text)
            let explicit = marker.flatMap { CurrencyDetector.code(forToken: $0, defaultCode: defaultCode) }
            let code = explicit ?? defaultCode
            guard let numberText = match.group(named: "num", in: text),
                  var minor = MinorUnitParser.minorUnits(from: numberText, currencyCode: code), minor > 0 else { continue }
            if match.group(named: "k", in: text) != nil {
                let (scaled, overflow) = minor.multipliedReportingOverflow(by: 1000)
                guard !overflow else { continue }
                minor = scaled
            }
            candidates.append(Candidate(
                range: match.range,
                found: FoundAmount(minorUnits: minor, explicitCode: explicit),
                hasCurrency: explicit != nil
            ))
        }
        let marked = candidates.filter(\.hasCurrency)
        let pool = marked.isEmpty ? candidates : marked
        guard let chosen = pool.max(by: { $0.found.minorUnits < $1.found.minorUnits }) else { return nil }
        blank(chosen.range)
        return chosen.found
    }

    // MARK: Title

    private static let fillerWords: Set<String> = [
        "for", "on", "at", "to", "of", "and", "with", "the", "a", "an", "i", "we", "my", "our", "it",
        "this", "that", "add", "log", "new", "expense", "paid", "spent", "just", "split", "shared",
        "each", "equally", "evenly", "total", "bill", "tab", "in", "by", "is", "was", "also", "me"
    ]

    func title() -> String {
        let pieces = text.components(separatedBy: "\u{00A6}")
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces).union(.symbols)) }
            .filter { !$0.isEmpty }
        var words = pieces.joined(separator: " ").split(separator: " ").map(String.init)
        func isFiller(_ word: String) -> Bool {
            Self.fillerWords.contains(word.folded.trimmingCharacters(in: .punctuationCharacters))
        }
        while let first = words.first, isFiller(first) { words.removeFirst() }
        while let last = words.last, isFiller(last) { words.removeLast() }
        return words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).sentenceCased
    }

    // MARK: Helpers

    private mutating func blank(_ range: NSRange) {
        guard let swiftRange = Range(range, in: text) else { return }
        text.replaceSubrange(swiftRange, with: Self.gap)
    }
}

private extension String {
    /// Fills the NAME and AMT placeholders used by the phrase patterns above.
    func replacingPlaceholders() -> String {
        replacingOccurrences(of: "NAME", with: #"[\p{L}][\p{L}\p{M}'’-]*"#)
            .replacingOccurrences(of: "AMT", with: #"[$€£¥₹]?\s?\d+(?:[.,]\d+)*"#)
    }

    func appending(_ other: String) -> String { self + other }
}
