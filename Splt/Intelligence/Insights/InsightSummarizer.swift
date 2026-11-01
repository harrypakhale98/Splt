import Foundation
import FoundationModels

/// Totals the app has already worked out for a group. The summarizer only describes them.
struct InsightInput: Equatable, Sendable {
    enum Kind: Sendable {
        case trip
        case household
        case other
    }

    struct CategoryAmount: Equatable, Sendable {
        var name: String
        var minorUnits: Int64

        init(name: String, minorUnits: Int64) {
            self.name = name
            self.minorUnits = minorUnits
        }
    }

    struct MemberAmount: Equatable, Sendable {
        var name: String
        /// What this person paid out of pocket.
        var paidMinorUnits: Int64

        init(name: String, paidMinorUnits: Int64) {
            self.name = name
            self.paidMinorUnits = paidMinorUnits
        }
    }

    var groupName: String
    var kind: Kind
    var expenseCount: Int
    var categories: [CategoryAmount]
    var members: [MemberAmount]

    init(
        groupName: String,
        kind: Kind = .other,
        expenseCount: Int,
        categories: [CategoryAmount],
        members: [MemberAmount] = []
    ) {
        self.groupName = groupName
        self.kind = kind
        self.expenseCount = expenseCount
        self.categories = categories
        self.members = members
    }

    var totalByCategory: Int64 { categories.reduce(0) { $0 + max($1.minorUnits, 0) } }
    var totalPaid: Int64 { members.reduce(0) { $0 + max($1.paidMinorUnits, 0) } }

    fileprivate var allowedNames: Set<String> {
        var names: Set<String> = [groupName.folded]
        for word in groupName.foldedWords { names.insert(word) }
        for category in categories { category.name.foldedWords.forEach { names.insert($0) } }
        for member in members { member.name.foldedWords.forEach { names.insert($0) } }
        return names
    }
}

/// Describes a group's spending in a sentence or two.
protocol InsightSummarizing: Sendable {
    /// Plain text, or nil when there is nothing worth saying yet.
    func summarize(_ input: InsightInput) async -> String?
}

/// Writes the sentences from a list of facts. Replaceable so tests need no model.
protocol InsightWriting: Sendable {
    func write(facts: String) async throws -> String
}

struct FoundationModelsInsightWriter: InsightWriting {
    func write(facts: String) async throws -> String {
        guard OnDeviceModel.isAvailable else { throw OnDeviceModel.TimedOut() }
        let answer = try await OnDeviceModel.respond(
            instructions: """
                You describe a group's shared spending in one or two short, friendly, plain sentences. \
                Use only the facts given. Never use digits, currency symbols, emoji or lists, and never \
                mention an amount. Only mention people and categories that appear in the facts.
                """,
            prompt: facts,
            generating: InsightAnswer.self,
            timeout: .seconds(6)
        )
        return answer.text
    }
}

@Generable(description: "One or two plain sentences about a group's spending.")
struct InsightAnswer: Sendable {
    @Guide(description: "One or two short sentences, no digits and no amounts.")
    var text: String
}

/// Uses the on-device model when it is available and its sentences pass the checks,
/// and a template otherwise. The two read alike, so people never notice which one ran.
struct InsightSummarizer: InsightSummarizing {
    var writer: (any InsightWriting)? = FoundationModelsInsightWriter()

    func summarize(_ input: InsightInput) async -> String? {
        guard input.expenseCount > 0, input.totalByCategory > 0 || input.totalPaid > 0 else { return nil }
        if let writer, let text = try? await writer.write(facts: Self.facts(for: input)),
           let checked = Self.validated(text, for: input) {
            return checked
        }
        return Self.template(for: input)
    }

    // MARK: Facts for the model

    static func facts(for input: InsightInput) -> String {
        var lines = ["Group: \(input.groupName)", "Expenses logged: \(input.expenseCount)"]
        let total = input.totalByCategory
        let ranked = input.categories.filter { $0.minorUnits > 0 }.sorted { $0.minorUnits > $1.minorUnits }
        for category in ranked.prefix(4) where total > 0 {
            lines.append("Category \(category.name): \(percent(category.minorUnits, of: total)) percent of spending")
        }
        let paid = input.totalPaid
        let payers = input.members.filter { $0.paidMinorUnits > 0 }.sorted { $0.paidMinorUnits > $1.paidMinorUnits }
        for member in payers.prefix(3) where paid > 0 {
            lines.append("\(member.name) paid \(percent(member.paidMinorUnits, of: paid)) percent of the bills")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Checking model text

    /// Accepts one or two short sentences with no numbers, no markup and no made-up names.
    static func validated(_ text: String, for input: InsightInput) -> String? {
        let cleaned = text.tidied
        guard !cleaned.isEmpty, cleaned.count <= 220 else { return nil }
        guard !cleaned.contains(where: { $0.isNumber || "$€£¥₹*#_`•-".contains($0) }) else { return nil }
        guard !cleaned.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) else { return nil }

        let sentences = cleaned.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.allSatisfy(\.isWhitespace) }
        guard (1...2).contains(sentences.count) else { return nil }

        let allowed = input.allowedNames
        for sentence in sentences {
            let words = sentence.split(separator: " ").map(String.init)
            for word in words.dropFirst() where word.first?.isUppercase == true {
                let folded = word.folded.trimmingCharacters(in: .punctuationCharacters)
                if !allowed.contains(folded) && !["i", "you"].contains(folded) { return nil }
            }
        }
        return cleaned.hasSuffix(".") || cleaned.hasSuffix("!") || cleaned.hasSuffix("?") ? cleaned : cleaned + "."
    }

    // MARK: Fallback sentences

    static func template(for input: InsightInput) -> String {
        let noun: String
        switch input.kind {
        case .trip: noun = "this trip"
        case .household: noun = "your shared spending"
        case .other: noun = "this group"
        }

        var sentences: [String] = []
        let total = input.totalByCategory
        let ranked = input.categories.filter { $0.minorUnits > 0 }.sorted { $0.minorUnits > $1.minorUnits }
        if let top = ranked.first, total > 0 {
            let share = percent(top.minorUnits, of: total)
            let name = top.name.lowercased()
            if share >= 50 {
                sentences.append("Most of \(noun) went to \(name).")
            } else if share >= 30 {
                sentences.append("\(top.name.sentenceCased) was the biggest part of \(noun).")
            } else if ranked.count >= 2 {
                sentences.append("Spending on \(noun) is spread across \(name) and \(ranked[1].name.lowercased()).")
            }
        }

        let payers = input.members.filter { $0.paidMinorUnits > 0 }.sorted { $0.paidMinorUnits > $1.paidMinorUnits }
        let paid = input.totalPaid
        if input.members.count >= 2, let lead = payers.first, paid > 0 {
            if percent(lead.paidMinorUnits, of: paid) >= 60 {
                sentences.append("\(lead.name) covered most of it.")
            } else if let last = payers.last, payers.count == input.members.count,
                      percent(lead.paidMinorUnits - last.paidMinorUnits, of: paid) <= 10 {
                sentences.append("Everyone has paid a similar amount.")
            }
        }

        if sentences.isEmpty {
            sentences.append(input.expenseCount == 1 ? "One expense so far." : "\(input.expenseCount) expenses so far.")
        }
        return sentences.joined(separator: " ")
    }

    /// Whole percent of `part` in `whole`, rounded to nearest, using integers only.
    static func percent(_ part: Int64, of whole: Int64) -> Int {
        guard whole > 0 else { return 0 }
        return Int((part * 100 + whole / 2) / whole)
    }
}
