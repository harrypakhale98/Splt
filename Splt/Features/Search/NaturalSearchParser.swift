import Foundation
import NaturalLanguage
import SpltCore

/// Reads a typed question such as "dinners Sam paid in March" into a filter, with no network and no model.
struct NaturalSearchParser {
    var people: [Person]
    var now: Date = Date()
    var calendar: Calendar = .current

    private struct Token {
        var text: String
        var folded: String
        var used = false
    }

    func parse(_ query: String) -> SearchFilter {
        var tokens = Self.tokens(in: query)
        var filter = SearchFilter()
        readPeriod(&tokens, into: &filter)
        readAmounts(&tokens, into: &filter)
        readPeople(&tokens, into: &filter)
        readCategory(&tokens, into: &filter)
        filter.terms = tokens.filter { !$0.used && !SearchVocabulary.stopWords.contains($0.folded) }.map(\.text)
        return filter
    }

    // MARK: Tokens

    private static func tokens(in query: String) -> [Token] {
        query.split(whereSeparator: \.isWhitespace).compactMap { piece in
            var text = String(piece).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?\"()"))
            if text.hasSuffix("'s") || text.hasSuffix("\u{2019}s") { text = String(text.dropLast(2)) }
            guard !text.isEmpty else { return nil }
            return Token(text: text, folded: text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
        }
    }

    private func words(_ tokens: [Token]) -> [String] {
        tokens.map { $0.used ? "" : $0.folded }
    }

    private func use(_ tokens: inout [Token], _ range: Range<Int>) {
        for index in range { tokens[index].used = true }
    }

    /// The first place a run of words appears in the unused tokens.
    private func find(_ phrase: [String], in tokens: [Token]) -> Range<Int>? {
        let all = words(tokens)
        guard !phrase.isEmpty, all.count >= phrase.count else { return nil }
        for start in 0...(all.count - phrase.count) where Array(all[start..<start + phrase.count]) == phrase {
            return start..<start + phrase.count
        }
        return nil
    }

    // MARK: Dates

    private func readPeriod(_ tokens: inout [Token], into filter: inout SearchFilter) {
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        let named: [([String], () -> Range<Date>?)] = [
            (["yesterday"], { calendar.date(byAdding: .day, value: -1, to: startOfToday).map { $0..<startOfToday } }),
            (["today"], { startOfToday..<tomorrow }),
            (["this", "week"], { interval(.weekOfYear, offset: 0) }),
            (["last", "week"], { interval(.weekOfYear, offset: -1) }),
            (["this", "month"], { interval(.month, offset: 0) }),
            (["last", "month"], { interval(.month, offset: -1) }),
            (["this", "year"], { interval(.year, offset: 0) }),
            (["last", "year"], { interval(.year, offset: -1) })
        ]
        for (phrase, range) in named {
            if let found = find(phrase, in: tokens), let value = range() {
                use(&tokens, found)
                filter.period = value
                return
            }
        }
        if readRecent(&tokens, into: &filter, startOfToday: startOfToday, tomorrow: tomorrow) { return }
        readMonthAndYear(&tokens, into: &filter)
    }

    private func interval(_ component: Calendar.Component, offset: Int) -> Range<Date>? {
        guard let shifted = calendar.date(byAdding: component, value: offset, to: now),
              let value = calendar.dateInterval(of: component, for: shifted) else { return nil }
        return value.start..<value.end
    }

    /// "last 10 days", "past 2 weeks", "past 3 months".
    private func readRecent(_ tokens: inout [Token], into filter: inout SearchFilter, startOfToday: Date, tomorrow: Date) -> Bool {
        let all = words(tokens)
        guard all.count >= 3 else { return false }
        for index in 0...(all.count - 3) where ["last", "past", "previous"].contains(all[index]) {
            guard let count = Int(all[index + 1]), count > 0, count <= 3650 else { continue }
            let unit: Calendar.Component
            switch all[index + 2] {
            case "day", "days": unit = .day
            case "week", "weeks": unit = .weekOfYear
            case "month", "months": unit = .month
            default: continue
            }
            guard let start = calendar.date(byAdding: unit, value: -count, to: startOfToday) else { continue }
            use(&tokens, index..<index + 3)
            filter.period = start..<tomorrow
            return true
        }
        return false
    }

    private func readMonthAndYear(_ tokens: inout [Token], into filter: inout SearchFilter) {
        let all = words(tokens)
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        for (index, word) in all.enumerated() {
            guard let month = SearchVocabulary.months[word] else { continue }
            let hasIn = index > 0 && ["in", "during", "of", "since"].contains(all[index - 1])
            // "may" is also a verb, so it needs the word "in" before it or a year after it
            let nextYear = index + 1 < all.count ? Self.year(all[index + 1]) : nil
            if word == "may" && !hasIn && nextYear == nil { continue }
            let isFriend = people.contains { !$0.isMe && Self.foldedWords($0.name).first == word }
            if isFriend && !hasIn && nextYear == nil { continue }
            var range = index..<index + 1
            if hasIn { range = index - 1..<range.upperBound }
            var year = nextYear
            if nextYear != nil { range = range.lowerBound..<range.upperBound + 1 }
            if year == nil { year = month <= currentMonth ? currentYear : currentYear - 1 }
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            use(&tokens, range)
            filter.period = start..<end
            return
        }
        for (index, word) in all.enumerated() {
            guard let year = Self.year(word),
                  let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { continue }
            let hasIn = index > 0 && ["in", "during", "of", "since"].contains(all[index - 1])
            use(&tokens, hasIn ? index - 1..<index + 1 : index..<index + 1)
            filter.period = start..<end
            return
        }
    }

    private static func year(_ word: String) -> Int? {
        guard word.count == 4, let value = Int(word), (1990...2100).contains(value) else { return nil }
        return value
    }

    // MARK: Amounts

    private func readAmounts(_ tokens: inout [Token], into filter: inout SearchFilter) {
        let minimum: [[String]] = [["more", "than"], ["at", "least"], ["over"], ["above"], ["exceeding"]]
        let maximum: [[String]] = [["less", "than"], ["at", "most"], ["under"], ["below"]]
        for (phrases, isMinimum) in [(minimum, true), (maximum, false)] {
            for phrase in phrases {
                guard let found = find(phrase, in: tokens), found.upperBound < tokens.count,
                      let value = Self.amount(tokens[found.upperBound].folded) else { continue }
                use(&tokens, found.lowerBound..<found.upperBound + 1)
                if isMinimum { filter.minAmount = value } else { filter.maxAmount = value }
            }
        }
    }

    private static func amount(_ word: String) -> Decimal? {
        let cleaned = word.filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty, cleaned.contains(where: \.isNumber) else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: People

    private func readPeople(_ tokens: inout [Token], into filter: inout SearchFilter) {
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard !tokens[index].used else { continue }
            let word = tokens[index].folded
            if ["i", "me"].contains(word), index + 1 < tokens.count,
               SearchVocabulary.payerVerbs.contains(tokens[index + 1].folded),
               let me = people.first(where: \.isMe) {
                filter.payer = me.id
                use(&tokens, index..<index + 2)
                continue
            }
            if word == "me", index > 0, tokens[index - 1].folded == "by", !tokens[index - 1].used,
               let me = people.first(where: \.isMe) {
                filter.payer = me.id
                let paid = index > 1 && tokens[index - 2].folded == "paid" && !tokens[index - 2].used
                use(&tokens, (paid ? index - 2 : index - 1)..<index + 1)
                continue
            }
            guard let (person, length) = match(at: index, in: tokens) else { continue }
            let range = index..<index + length
            let before = index > 0 && !tokens[index - 1].used ? tokens[index - 1].folded : nil
            let beforeThat = index > 1 && !tokens[index - 2].used ? tokens[index - 2].folded : nil
            let after = range.upperBound < tokens.count && !tokens[range.upperBound].used ? tokens[range.upperBound].folded : nil

            if let after, SearchVocabulary.payerVerbs.contains(after) {
                filter.payer = person.id
                use(&tokens, index..<range.upperBound + 1)
            } else if before == "by" {
                filter.payer = person.id
                let start = beforeThat == "paid" ? index - 2 : index - 1
                use(&tokens, start..<range.upperBound)
            } else {
                filter.participant = person.id
                use(&tokens, range)
                if let before, ["with", "between"].contains(before) { tokens[index - 1].used = true }
            }
        }
    }

    /// The person whose name starts at `index`, and how many words the name takes.
    private func match(at index: Int, in tokens: [Token]) -> (Person, Int)? {
        if index + 1 < tokens.count, !tokens[index + 1].used {
            let pair = [tokens[index].folded, tokens[index + 1].folded]
            let full = people.filter { !$0.isMe && Self.foldedWords($0.name) == pair }
            if full.count == 1, let person = full.first { return (person, 2) }
        }
        let word = tokens[index].folded
        guard word.count >= 2, !SearchVocabulary.stopWords.contains(word),
              SearchVocabulary.categoryWords[word] == nil else { return nil }
        let matches = people.filter { person in
            guard !person.isMe else { return false }
            let parts = Self.foldedWords(person.name)
            return parts.first == word
        }
        return matches.count == 1 ? matches.first.map { ($0, 1) } : nil
    }

    private static func foldedWords(_ name: String) -> [String] {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }

    // MARK: Category

    private func readCategory(_ tokens: inout [Token], into filter: inout SearchFilter) {
        for index in tokens.indices where !tokens[index].used {
            let word = tokens[index].folded
            // "show me dinners" asks to see dinners, not for a show
            if SearchVocabulary.stopWords.contains(word) { continue }
            let lemma = Self.lemma(of: word)
            guard let category = SearchVocabulary.categoryWords[lemma] ?? SearchVocabulary.categoryWords[word] else { continue }
            filter.category = category
            filter.categoryWord = lemma
            tokens[index].used = true
            return
        }
    }

    private static func lemma(of word: String) -> String {
        if SearchVocabulary.categoryWords[word] != nil { return word }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        let tag = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0
        if let value = tag?.rawValue.lowercased(), SearchVocabulary.categoryWords[value] != nil { return value }
        if word.hasSuffix("es"), SearchVocabulary.categoryWords[String(word.dropLast(2))] != nil { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), SearchVocabulary.categoryWords[String(word.dropLast())] != nil { return String(word.dropLast()) }
        return word
    }
}
