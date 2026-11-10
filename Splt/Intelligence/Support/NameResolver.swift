import Foundation
import NaturalLanguage

/// Decides whether a word in a note is a person, and which known person it means.
struct NameResolver: Sendable {
    /// People already in the group, as displayed.
    let candidates: [String]
    /// Folded names that the language tagger found in the note itself.
    let taggedNames: Set<String>

    init(candidates: [String], text: String = "") {
        self.candidates = candidates
        self.taggedNames = Self.personalNames(in: text)
    }

    private static let stopWords: Set<String> = [
        "i", "me", "my", "myself", "we", "us", "our", "you", "he", "she", "they", "them", "it",
        "and", "or", "the", "a", "an", "with", "for", "on", "at", "to", "of", "in", "by", "from",
        "also", "both", "each", "all", "everyone", "everybody", "someone", "somebody", "friends",
        "friend", "family", "team", "group", "people", "guys", "others", "other", "paid", "pays",
        "owes", "owe", "split", "equally", "evenly", "less", "more", "extra", "total", "tip", "tax",
        "dinner", "lunch", "breakfast", "today", "tomorrow", "yesterday", "tonight"
    ]

    static func isStopWord(_ word: String) -> Bool {
        stopWords.contains(word.folded)
    }

    /// True for "me", "I", "myself": the person typing, who is never listed as another participant.
    static func refersToWriter(_ word: String) -> Bool {
        ["me", "i", "myself", "mine"].contains(word.folded)
    }

    /// The group member this text names, when exactly one member matches by full name or first name.
    func matchingCandidate(for typed: String) -> String? {
        let words = typed.foldedWords
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        let exact = candidates.filter { $0.foldedWords.joined(separator: " ") == joined }
        if exact.count == 1 { return exact[0] }
        guard words.count == 1 else { return nil }
        let byFirstName = candidates.filter { $0.foldedWords.first == words[0] }
        return byFirstName.count == 1 ? byFirstName[0] : nil
    }

    /// Whether a typed word may be a person's name: a group member, a name the tagger found,
    /// or a capitalised word that is not an everyday expense word.
    func plausibleName(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.count >= 2, trimmed.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "\u{2019}" || $0 == "-" }) else {
            return nil
        }
        if let candidate = matchingCandidate(for: trimmed) { return candidate }
        guard !Self.isStopWord(trimmed), !KeywordCategoryTable.standard.recognises(word: trimmed) else { return nil }
        let startsUppercase = trimmed.first?.isUppercase == true
        if startsUppercase || taggedNames.contains(trimmed.folded) {
            return trimmed.sentenceCased
        }
        return nil
    }

    /// A two word name: a group member written in full, or two capitalised words that are both plausible names.
    /// When the second word alone is already a member, the first is not part of the name: "Camping Sam".
    func fullName(_ first: String, _ second: String) -> String? {
        if let candidate = matchingCandidate(for: "\(first) \(second)") { return candidate }
        guard first.first?.isUppercase == true, second.first?.isUppercase == true,
              matchingCandidate(for: first) == nil, matchingCandidate(for: second) == nil,
              plausibleName(first) != nil, plausibleName(second) != nil else { return nil }
        return "\(first.sentenceCased) \(second.sentenceCased)"
    }

    /// Whether a word reads as a name right now, used to avoid gluing a third word onto a full name.
    func looksLikeName(_ word: String) -> Bool {
        plausibleName(word) != nil && !["and", "plus", "n"].contains(word.lowercased())
    }

    /// Accepts a name from a model or another source: a member, or a new name that is written in `text`.
    func validatedName(_ typed: String, writtenIn text: String) -> String? {
        let name = typed.tidied
        guard !name.isEmpty, !Self.refersToWriter(name), !Self.isStopWord(name) else { return nil }
        if let candidate = matchingCandidate(for: name) {
            return text.foldedWords.contains(name.foldedWords.first ?? "") ? candidate : nil
        }
        let written = Set(text.foldedWords)
        guard name.foldedWords.allSatisfy(written.contains) else { return nil }
        // "pizza" is what was bought, and "Dinner Sam" is the member Sam with a stray word
        let words = name.split(separator: " ").map(String.init)
        guard !words.contains(where: { Self.isStopWord($0) || KeywordCategoryTable.standard.recognises(word: $0) }),
              words.count == 1 || !words.contains(where: { matchingCandidate(for: $0) != nil }) else { return nil }
        guard name.allSatisfy({ $0.isLetter || $0 == " " || $0 == "'" || $0 == "\u{2019}" || $0 == "-" }) else { return nil }
        return name.split(separator: " ").map { String($0).sentenceCased }.joined(separator: " ")
    }

    private static func personalNames(in text: String) -> Set<String> {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names = Set<String>()
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if tag == .personalName {
                names.insert(String(text[range]).folded)
            }
            return true
        }
        return names
    }
}
