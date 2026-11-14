import AppIntents
import Foundation
import FoundationModels
import SpltCore

/// Saves a payment to To Split. Made for a Shortcuts Wallet automation, which runs it at the checkout,
/// often on a locked phone: so it never asks for Face ID, never opens the app and never adds an expense.
/// It reads nothing back but the group names it shows in a nudge.
struct LogPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Payment"
    static let description = IntentDescription(
        "Saves a payment to Splt's To Split list so you can share it later. Use it in a Wallet automation in Shortcuts."
    )
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Amount")
    var amount: IntentCurrencyAmount

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let money = PaymentAmount.money(amount.amount, currencyCode: amount.currencyCode) else {
            throw IntentError(.badAmount)
        }
        PaymentInbox.shared.capture(merchant: merchant ?? "", amount: money, date: date ?? Date(), source: .wallet)
        return .result()
    }
}

/// Saves a payment read from a bank text or a receipt email, for a Shortcuts Message or Email automation.
/// Codes, offers and refunds are skipped quietly, and the text itself is never kept.
struct LogPaymentTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Payment from Text"
    static let description = IntentDescription(
        "Reads a payment from a bank text or receipt email and saves it to To Split. One-time codes, offers and refunds are skipped."
    )
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log the payment in \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let limited = String(text.prefix(2_000))
        guard let parsed = PaymentTextParser.parse(limited) else { return .result() }
        var merchant = parsed.merchant
        if merchant == nil { merchant = await MerchantGuesser.guess(from: limited) }
        PaymentInbox.shared.capture(merchant: merchant ?? "", amount: parsed.amount, date: Date(), source: .text)
        return .result()
    }
}

/// Opens Splt on the newest payment waiting to be split.
struct SplitLastPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Split Last Payment"
    static let description = IntentDescription("Opens the newest payment in To Split, ready to split.")

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        PaymentInbox.shared.reload()
        let link = PaymentInbox.shared.state.pending.first.map { DeepLink.payment($0.id).url } ?? DeepLink.activity.url
        return .result(opensIntent: OpenURLIntent(link))
    }
}

/// A Focus filter: while a Focus such as Travel is on, payments go to the group it names.
struct SpltFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Set Splt Group"
    static let description = IntentDescription("Sends payments caught during this Focus to one group, such as a trip.")

    @Parameter(title: "Group")
    var group: GroupEntity?

    var displayRepresentation: DisplayRepresentation {
        if let group {
            DisplayRepresentation(title: "Splt", subtitle: "Payments go to \(group.name)")
        } else {
            DisplayRepresentation(title: "Splt", subtitle: "Payments go to the usual group")
        }
    }

    func perform() async throws -> some IntentResult {
        let defaults = PaymentInboxFile.sharedDefaults
        if let group {
            defaults.set(group.id.uuidString, forKey: SplitTargetPicker.focusGroupKey)
        } else {
            defaults.removeObject(forKey: SplitTargetPicker.focusGroupKey)
        }
        return .result()
    }
}

/// Fills in a merchant the rules couldn't find, when the on-device model is there. Only the name:
/// whether something is a payment, and for how much, is always the rules' call.
enum MerchantGuesser {
    @Generable
    struct Guess: Sendable {
        @Guide(description: "The shop, restaurant or person paid, as a short name. Empty if the text doesn't say.")
        var merchant: String
    }

    static func guess(from text: String) async -> String? {
        guard OnDeviceModel.isAvailable else { return nil }
        let guess = try? await OnDeviceModel.respond(
            instructions: "You read bank payment texts and name who was paid. Never invent a name.",
            prompt: text,
            generating: Guess.self,
            timeout: .seconds(4)
        )
        let name = guess?.merchant.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty || name.count > 60 ? nil : name
    }
}
