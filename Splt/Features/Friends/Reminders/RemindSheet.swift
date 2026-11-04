import SpltCore
import SwiftUI

/// Asks a friend to pay you back: share a friendly message, or schedule a reminder for yourself.
struct RemindSheet: View {
    let friend: Person
    /// What the friend owes you, one amount per currency.
    let owed: [Money]
    var groupNames: [String] = []
    var scheduler = ReminderScheduler()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(Router.self) private var router
    @State private var outcome: ReminderScheduler.Outcome?
    @State private var showsSettingsPrompt = false

    private var message: String {
        let text = ReminderMessage.shareText(friendName: friend.name, amounts: owed, groupNames: groupNames, locale: locale)
        guard let line = AccountProfile.shared.paymentLine else { return text }
        return text + "\n\n" + line
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    Text(message)
                        .textSelection(.enabled)
                    ShareLink(item: message) {
                        Label("Send Reminder", systemImage: "paperplane")
                    }
                }
                Section {
                    ForEach(ReminderDelay.allCases) { delay in
                        Button(delay.title) { schedule(delay) }
                    }
                } header: {
                    Text("Remind Me")
                } footer: {
                    footer
                }
            }
            .navigationTitle("Remind \(ReminderMessage.firstName(friend.name))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", role: .close) { dismiss() }
                }
            }
            .alert("Turn On Notifications", isPresented: $showsSettingsPrompt) {
                Button("Open Settings") {
                    dismiss()
                    router.push(.settings, in: .account)
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Reminders need Notifications turned on in Splt's settings.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var footer: some View {
        switch outcome {
        case .scheduled(let date):
            Label("Reminder set for \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle")
        case .notAllowed:
            Text("Splt isn't allowed to send notifications. You can change this in the Settings app.")
        case .blocked:
            Text("You blocked this person, so Splt won't remind you about them.")
        default:
            Text("You get a quiet notification on your device. Nothing is sent to anyone.")
        }
    }

    private func schedule(_ delay: ReminderDelay) {
        Task {
            let result = await scheduler.schedule(for: friend, owed: owed, after: delay)
            outcome = result
            if case .scheduled(let date) = result {
                let time = date.formatted(date: .abbreviated, time: .shortened)
                AccessibilityNotification.Announcement(String(localized: "Reminder set for \(time)")).post()
            }
            if result == .turnedOffInSettings { showsSettingsPrompt = true }
        }
    }
}

#if DEBUG
#Preview {
    RemindSheet(
        friend: Person(name: "Maya Chen"),
        owed: [Money(minorUnits: 4_250, currencyCode: "EUR")],
        groupNames: ["Lisbon Trip"]
    )
    .environment(Router())
}
#endif
