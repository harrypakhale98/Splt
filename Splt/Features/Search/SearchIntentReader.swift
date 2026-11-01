import Foundation
import FoundationModels
import SpltCore

/// What the on-device model understood from a question. Untrusted: it is checked before use.
struct SearchIntentReading: Equatable, Sendable {
    var words: [String] = []
    var paidBy = ""
    var withPerson = ""
    var category = ""
    var month = 0
    var year = 0
    var minimumAmount = 0
    var maximumAmount = 0
}

protocol SearchIntentReader: Sendable {
    var isAvailable: Bool { get }
    func read(_ query: String, names: [String]) async throws -> SearchIntentReading
}

struct FoundationModelsSearchReader: SearchIntentReader {
    var isAvailable: Bool { OnDeviceModel.isAvailable }

    func read(_ query: String, names: [String]) async throws -> SearchIntentReading {
        let known = names.isEmpty ? "No people are known." : "Known people: \(names.joined(separator: ", "))."
        let categories = ExpenseCategory.allCases.map(\.rawValue).joined(separator: ", ")
        let answer = try await OnDeviceModel.respond(
            instructions: """
                You turn a short question about shared expenses into search parts. The question may be \
                in any language. Copy only what is written and never guess. \(known) \
                Categories: \(categories). Use the spelling of a known person when a name matches.
                """,
            prompt: "Question: \(query)",
            generating: SearchIntentAnswer.self,
            timeout: .seconds(4)
        )
        return answer.reading
    }
}

@Generable(description: "The parts of a question about shared expenses.")
struct SearchIntentAnswer: Sendable {
    @Guide(description: "Words to look for in an expense title, copied as written. Empty if none.")
    var words: [String]

    @Guide(description: "The person who paid, as written. Empty if not stated.")
    var paidBy: String

    @Guide(description: "Another person who took part, as written. Empty if not stated.")
    var withPerson: String

    @Guide(description: "One category from the list that the question is about, or empty.")
    var category: String

    @Guide(description: "The month as a number from 1 to 12, or 0 if no month is written.")
    var month: Int

    @Guide(description: "A four digit year, or 0 if no year is written.")
    var year: Int

    @Guide(description: "Only spending above this amount, or 0.")
    var minimumAmount: Int

    @Guide(description: "Only spending below this amount, or 0.")
    var maximumAmount: Int

    var reading: SearchIntentReading {
        SearchIntentReading(
            words: words, paidBy: paidBy, withPerson: withPerson, category: category, month: month, year: year,
            minimumAmount: minimumAmount, maximumAmount: maximumAmount
        )
    }
}

/// Turns the model's answer into a filter, dropping anything that does not check out.
struct SearchIntentValidator {
    var people: [Person]
    var now: Date = Date()
    var calendar: Calendar = .current

    func filter(from reading: SearchIntentReading, query: String) -> SearchFilter {
        var filter = SearchFilter()
        let written = Set(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        filter.terms = reading.words.map(\.tidied).filter { word in
            !word.isEmpty && word.foldedWords.allSatisfy(written.contains)
        }
        filter.payer = resolve(reading.paidBy, written: written)
        filter.participant = resolve(reading.withPerson, written: written)
        filter.category = ExpenseCategory(rawValue: reading.category.lowercased()).flatMap { $0 == .general || $0 == .other ? nil : $0 }
        filter.period = period(month: reading.month, year: reading.year)
        if reading.minimumAmount > 0 { filter.minAmount = Decimal(reading.minimumAmount) }
        if reading.maximumAmount > 0 { filter.maxAmount = Decimal(reading.maximumAmount) }
        return filter
    }

    private func resolve(_ name: String, written: Set<String>) -> PersonID? {
        let words = name.foldedWords
        guard !words.isEmpty, words.allSatisfy(written.contains) else { return nil }
        let matches = people.filter { person in
            guard !person.isMe else { return false }
            let parts = person.name.foldedWords
            return parts == words || (words.count == 1 && parts.first == words.first)
        }
        return matches.count == 1 ? matches.first?.id : nil
    }

    private func period(month: Int, year: Int) -> Range<Date>? {
        guard (1...12).contains(month) || (1990...2100).contains(year) else { return nil }
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let chosenYear = (1990...2100).contains(year) ? year : (month <= currentMonth ? currentYear : currentYear - 1)
        guard (1...12).contains(month) else {
            guard let start = calendar.date(from: DateComponents(year: chosenYear, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
            return start..<end
        }
        guard let start = calendar.date(from: DateComponents(year: chosenYear, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return start..<end
    }
}
