import Foundation
import FoundationModels

/// Tidies merchant and item names read from a receipt. Amounts are never touched.
protocol ReceiptNameRepairing: Sendable {
    func repairNames(in receipt: ParsedReceipt) async -> ParsedReceipt
}

/// Asks the on-device model to fix recognition slips and expand printer abbreviations, such as
/// "CHKN CAESR SAL" to "Chicken Caesar Salad". Every suggestion is checked against the printed
/// text, and a name that strays too far is ignored.
struct FoundationModelsNameRepairer: ReceiptNameRepairing {
    static let maximumItems = 40

    func repairNames(in receipt: ParsedReceipt) async -> ParsedReceipt {
        guard OnDeviceModel.isAvailable, !receipt.items.isEmpty, receipt.items.count <= Self.maximumItems else {
            return receipt
        }
        let numbered = receipt.items.enumerated().map { "\($0.offset + 1). \($0.element.name)" }.joined(separator: "\n")
        let prompt = """
            Merchant: \(receipt.merchant ?? "unknown")
            Items:
            \(numbered)
            """
        let generated = try? await OnDeviceModel.respond(
            instructions: """
                You tidy text read from a shop receipt by a text recogniser. Fix obvious misread \
                characters and expand printer abbreviations into plain product names. Keep the same \
                language, the same order and exactly one name per input line. Do not add, merge or \
                drop items, and do not invent details that are not implied by the text.
                """,
            prompt: prompt,
            generating: GeneratedReceiptNames.self,
            timeout: .seconds(8)
        )
        guard let generated else { return receipt }
        return Self.apply(generated.merchant, generated.items, to: receipt)
    }

    /// Applies suggestions that pass the checks. Pure, so it is tested without a model.
    static func apply(_ merchant: String, _ items: [String], to receipt: ParsedReceipt) -> ParsedReceipt {
        var repaired = receipt
        guard items.count == receipt.items.count else { return receipt }
        for (index, proposed) in items.enumerated() {
            let original = receipt.items[index].name
            if ReceiptNameCheck.accepts(proposed, replacing: original) {
                repaired.items[index].name = proposed.tidied
            }
        }
        if let original = receipt.merchant, ReceiptNameCheck.accepts(merchant, replacing: original) {
            repaired.merchant = merchant.tidied
        }
        return repaired
    }
}

enum ReceiptNameCheck {
    /// A repaired name must be short, contain letters and stay close to what was printed.
    static func accepts(_ proposed: String, replacing original: String) -> Bool {
        let new = proposed.tidied
        guard !new.isEmpty, new.count <= 60, new.contains(where: \.isLetter) else { return false }
        let before = original.folded.filter { $0.isLetter || $0.isNumber }
        let after = new.folded.filter { $0.isLetter || $0.isNumber }
        guard !before.isEmpty else { return false }
        let allowed = max(3, Int(Double(max(before.count, after.count)) * 0.6))
        return EditDistance.between(before, after) <= allowed
    }
}

@Generable(description: "Tidied names for a receipt.")
struct GeneratedReceiptNames: Sendable {
    @Guide(description: "The tidied merchant name, or the input merchant unchanged if it looks right.")
    var merchant: String

    @Guide(description: "One tidied name per input item, in the same order, with exactly as many entries as there are items.")
    var items: [String]
}
