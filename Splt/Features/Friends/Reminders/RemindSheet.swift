import SpltCore
import SwiftUI

/// Asks a friend to pay you back: remind them in Splt when you share a group, share a short
/// message, or schedule a reminder for yourself.
struct RemindSheet: View {
    let friend: Person
    /// What the friend owes you, one amount per currency.
    let owed: [Money]
    var groupNames: [String] = []
    var scheduler = ReminderScheduler()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services
    @Environment(\.groupSharing) private var sharing
    @State private var inApp: InAppReminder.State = .unavailable
    @State private var inAppFailed = false
    @State private var outcome: ReminderScheduler.Outcome?
    @State private var opensAccount = false
    @State private var showsSettingsPrompt = false

    private var message: String {
        let text = ReminderMessage.shareText(friendName: friend.name, amounts: owed, groupNames: groupNames, locale: locale)
        guard let line = AccountProfile.shared.paymentLine else { return text }
        return text + "\n\n" + line
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RaisedRows {
                        Text(message)
                            .textSelection(.enabled)
                        if inApp != .unavailable {
                            Button("Remind in Splt", systemImage: "bell", action: remindInApp)
                                .disabled(!inApp.isReady)
                        }
                        ShareLink(item: message, subject: Text("A quick reminder")) {
                            Label("Send Reminder", systemImage: "paperplane")
                        }
                    }
                } header: {
                    SectionHeader("Message")
                        .padding(.horizontal, Depth.pageMargin + 4)
                } footer: {
                    inAppFooter
                        .padding(.horizontal, Depth.pageMargin + 4)
                }
                .raisedSection()
                Section {
                    RaisedRows {
                        ForEach(ReminderDelay.allCases) { delay in
                            Button(delay.title) { schedule(delay) }
                        }
                    }
                } header: {
                    SectionHeader("Remind me")
                        .padding(.horizontal, Depth.pageMargin + 4)
                } footer: {
                    footer
                        .padding(.horizontal, Depth.pageMargin + 4)
                }
                .raisedSection()
            }
            .paperBackground()
            .navigationTitle("Remind \(ReminderMessage.firstName(friend.name))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .close) { dismiss() }
                }
            }
            // Account is a sheet too, so it opens only once this one has gone
            .onDisappear {
                if opensAccount { router.openAccount() }
            }
            .task { await loadInApp() }
            .alert("Couldn't Send", isPresented: $inAppFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The reminder couldn't be saved. Please try again.")
            }
            .alert("Turn On Notifications", isPresented: $showsSettingsPrompt) {
                Button("Open Settings") {
                    opensAccount = true
                    dismiss()
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Reminders need notifications turned on in Account.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var inAppFooter: some View {
        let first = ReminderMessage.firstName(friend.name)
        switch inApp {
        case .unavailable:
            EmptyView()
        case .ready:
            Text("\(first) gets a notification from Splt.")
        case .sentToday:
            Text("You already reminded \(first) in Splt today. You can again tomorrow.")
        case .sent:
            Text("Sent. \(first) will see it in Splt.")
        }
    }

    private func loadInApp() async {
        guard let services else { return }
        var synced = await sharing.groupsSharedWithMe()
        let groups = (try? services.groups.groups(includeArchived: false)) ?? []
        for group in groups where group.memberIDs.contains(friend.id) && !synced.contains(group.id) {
            if await sharing.isSharedByMe(groupID: group.id) { synced.insert(group.id) }
        }
        inApp = InAppReminder(services: services).state(for: friend, synced: synced)
    }

    private func remindInApp() {
        guard let services, case .ready(let targets) = inApp else { return }
        do {
            try InAppReminder(services: services).send(to: friend.id, targets: targets)
            inApp = .sent
            AccessibilityNotification.Announcement(String(localized: "Reminder sent")).post()
        } catch {
            inAppFailed = true
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch outcome {
        case .scheduled(let date):
            Text("Reminder set for \(date.formatted(date: .abbreviated, time: .shortened))")
        case .notAllowed:
            Text("Notifications are turned off in the Settings app.")
        case .blocked:
            Text("You blocked this person, so there's no reminder.")
        default:
            Text("Only you get this notification.")
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
