import AppIntents
import Foundation

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Adds an expense you paid and splits it equally.")
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "What For", requestValueDialog: "What was it for?")
    var title: String

    @Parameter(title: "Amount", requestValueDialog: "How much was it?")
    var amount: Double

    @Parameter(title: "Group")
    var group: GroupEntity?

    @Parameter(title: "Friend")
    var friend: FriendEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$title) for \(\.$amount)") {
            \.$group
            \.$friend
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentLock.requireUnlocked()
        guard let services = IntentServices.shared.live() else { throw IntentError.noStorage }
        do {
            let added = try IntentActions(services: services).addExpense(
                title: title, amount: amount, group: group?.id, friend: friend?.id
            )
            let total = MoneyFormatting.magnitudeString(added.amount)
            return .result(dialog: "Added \(added.title), \(total), to \(added.groupName).")
        } catch let failure as IntentActions.Failure {
            throw IntentError(failure)
        }
    }
}

struct SettleUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Settle Up"
    static let description = IntentDescription("Opens Splt ready to settle up with a friend.")

    @Parameter(title: "Friend", requestValueDialog: "Who do you want to settle up with?")
    var friend: FriendEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Settle up with \(\.$friend)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.settle(friend.id).url))
    }
}

struct ViewBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "View Balance"
    static let description = IntentDescription("Says what you owe or are owed, overall or with one friend or group.")
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Friend")
    var friend: FriendEntity?

    @Parameter(title: "Group")
    var group: GroupEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("View balance with \(\.$friend)") {
            \.$group
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentLock.requireUnlocked()
        guard let services = IntentServices.shared.live() else { throw IntentError.noStorage }
        do {
            let text = try IntentActions(services: services).balanceSentence(friend: friend?.id, group: group?.id)
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch let failure as IntentActions.Failure {
            throw IntentError(failure)
        }
    }
}

/// What Siri says when an intent cannot finish.
struct IntentError: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource

    static let noStorage = IntentError(localizedStringResource: "Splt couldn't open its data.")
    static let locked = IntentError(localizedStringResource: "Splt is locked. Unlock it to continue.")

    init(localizedStringResource: LocalizedStringResource) {
        self.localizedStringResource = localizedStringResource
    }

    init(_ failure: IntentActions.Failure) {
        switch failure {
        case .noGroup: self.init(localizedStringResource: "Create a group in Splt first.")
        case .badAmount: self.init(localizedStringResource: "That isn't an amount Splt can add.")
        case .unknownFriend: self.init(localizedStringResource: "Splt can't find that friend.")
        case .unknownGroup: self.init(localizedStringResource: "Splt can't find that group.")
        case .noStorage, .saveFailed: self.init(localizedStringResource: "Splt couldn't save that. Please try again.")
        }
    }
}

struct SpltShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Add a bill to \(.applicationName)",
                "Split a bill with \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: SettleUpIntent(),
            phrases: [
                "Settle up with \(\.$friend) in \(.applicationName)",
                "Pay back \(\.$friend) in \(.applicationName)"
            ],
            shortTitle: "Settle Up",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: ViewBalanceIntent(),
            phrases: [
                "What do I owe in \(.applicationName)",
                "Check my balance in \(.applicationName)"
            ],
            shortTitle: "View Balance",
            systemImageName: "scalemass"
        )
    }
}
