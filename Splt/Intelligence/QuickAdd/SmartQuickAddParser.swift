import Foundation
import SpltCore

/// The quick add entry point. Reads a note with the on-device model when it is available and
/// checks every field in plain code. Anything the model gets wrong or leaves out comes from the
/// rule based parser, so the result is always usable and no error ever reaches the person.
struct SmartQuickAddParser: QuickAddParsing {
    var rules = RuleBasedQuickAddParser()
    var reader: (any QuickAddReader)? = FoundationModelsQuickAddReader()
    var categories: any CategorySuggesting = CategorySuggester()

    func parse(_ text: String, context: QuickAddContext) async -> QuickAddDraft {
        let normalized = NumberWords.replacingSpelledNumbers(in: text.tidied)
        var draft = rules.parseNow(normalized, context: context)
        guard !normalized.isEmpty else { return draft }

        if let reader, reader.isAvailable, normalized.count <= FoundationModelsQuickAddReader.maximumCharacters,
           let reading = try? await reader.read(normalized, context: context) {
            let checked = QuickAddValidator.validate(reading, text: normalized, context: context)
            draft = Self.merge(rules: draft, model: checked)
        }

        if draft.category == nil, !draft.title.isEmpty {
            draft.category = await categories.suggest(title: draft.title, merchant: nil)?.category
        }
        return draft
    }

    /// Takes the amount, title and people from the checked model reading when it has them, otherwise
    /// from the rules. The payer and the direction of an adjustment stay as the rules read them.
    static func merge(rules: QuickAddDraft, model: QuickAddDraft) -> QuickAddDraft {
        var merged = rules
        var usedModel = false

        if model.amount != nil {
            merged.amount = model.amount
            merged.currencyHint = model.currencyHint
            usedModel = true
        }
        if !model.title.isEmpty {
            merged.title = model.title
            usedModel = true
        }
        if !model.participantNames.isEmpty {
            merged.participantNames = model.participantNames
            usedModel = true
        }
        // The rules read who paid and which way a share moves from fixed phrases, so the model may
        // fill those in but never change them.
        if model.payer != nil, rules.payer == nil || rules.payer == model.payer {
            merged.payer = model.payer
            usedModel = true
        }
        if case .adjustments(let read) = rules.splitHint, case .adjustments(let added) = model.splitHint {
            let known = Set(read.map(\.name.folded))
            merged.splitHint = .adjustments(read + added.filter { !known.contains($0.name.folded) })
            usedModel = true
        } else if model.splitHint != nil {
            merged.splitHint = model.splitHint
            usedModel = true
        }
        merged.source = usedModel ? .model : .rules
        includeNamedPeople(in: &merged)
        return merged
    }

    /// Anyone named as payer or in a share is also a participant.
    private static func includeNamedPeople(in draft: inout QuickAddDraft) {
        var names: [String] = []
        if let payer = draft.payerName { names.append(payer) }
        switch draft.splitHint {
        case .adjustments(let shares), .exactAmounts(let shares): names += shares.map(\.name)
        case .equal, nil: break
        }
        for name in names where !draft.participantNames.contains(where: { $0.folded == name.folded }) {
            draft.participantNames.append(name)
        }
    }
}
