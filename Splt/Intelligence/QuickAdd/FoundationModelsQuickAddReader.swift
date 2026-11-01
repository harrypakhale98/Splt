import Foundation
import FoundationModels

/// Reads a note with the on-device language model and returns its untrusted answer.
protocol QuickAddReader: Sendable {
    var isAvailable: Bool { get }
    func read(_ text: String, context: QuickAddContext) async throws -> QuickAddReading
}

struct FoundationModelsQuickAddReader: QuickAddReader {
    /// Longest note worth sending. A quick add note is a line, not a paragraph.
    static let maximumCharacters = 240

    var isAvailable: Bool { OnDeviceModel.isAvailable }

    func read(_ text: String, context: QuickAddContext) async throws -> QuickAddReading {
        let known = context.candidateNames.isEmpty
            ? "No other people are known yet."
            : "People already in the group: \(context.candidateNames.joined(separator: ", "))."
        let generated = try await OnDeviceModel.respond(
            instructions: """
                You read short notes people type or speak to log a shared expense, such as \
                "dinner 60 with Sam and Priya, I paid, Priya owes 10 less". The note may be in any \
                language. Copy only what is written. Never calculate, convert or guess. \
                The amount is the price, never a count of people or items, a time or a date. \
                \(known) Use the group spelling when a name matches.
                """,
            prompt: "Note: \(text)",
            generating: GeneratedQuickAdd.self
        )
        return generated.reading
    }
}

@Generable(description: "The parts of a short note about a shared expense.")
struct GeneratedQuickAdd: Sendable {
    @Guide(description: "What was bought, in the writer's own words, without the amount or the people. Empty if not stated.")
    var title: String

    @Guide(description: "The price copied as written with a period for decimals and no symbol, like 60 or 12.50. Empty if no price is written.")
    var amount: String

    @Guide(description: "ISO 4217 currency code only if a currency is written, like USD or EUR. Otherwise empty.")
    var currency: String

    @Guide(description: "Other people the expense is shared with, as written. Never the writer (I, me, my). Empty if none.")
    var participants: [String]

    @Guide(description: "Who paid: the word me if the writer paid, a name if someone else paid, or empty if not stated.")
    var payer: String

    @Guide(description: "adjustments when someone owes more or less than the others, equal when the note asks for an even split, otherwise none.")
    var splitKind: GeneratedSplitKind

    @Guide(description: "People who owe more or less than an even share. Empty unless splitKind is adjustments.")
    var adjustments: [GeneratedAdjustment]

    var reading: QuickAddReading {
        QuickAddReading(
            title: title,
            amount: amount,
            currency: currency,
            participants: participants,
            payer: payer,
            split: {
                switch splitKind {
                case .none: .unspecified
                case .equal: .equal
                case .adjustments: .adjustments
                }
            }(),
            adjustments: adjustments.map {
                QuickAddReading.Adjustment(name: $0.name, amount: $0.amount, isLess: $0.direction == .less)
            }
        )
    }
}

@Generable
enum GeneratedSplitKind: Sendable {
    case none
    case equal
    case adjustments
}

@Generable
enum GeneratedDirection: Sendable {
    case less
    case more
}

@Generable(description: "One person who owes more or less than an even share.")
struct GeneratedAdjustment: Sendable {
    @Guide(description: "The person's name as written.")
    var name: String

    @Guide(description: "How much more or less, copied as written with a period for decimals.")
    var amount: String

    @Guide(description: "less if they owe less, more if they owe more.")
    var direction: GeneratedDirection
}
