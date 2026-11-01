import SwiftUI

struct SettingsView: View {
    private let preferences = Preferences()

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    CurrencyPickerView()
                } label: {
                    LabeledContent(
                        "Default Currency",
                        value: CurrencyCatalog.name(for: preferences.defaultCurrencyCode)
                    )
                }
                LabeledContent("Appearance") {
                    Text("Same as System")
                }
            } header: {
                Text("General")
            } footer: {
                Text("New groups start with this currency. Splt follows the light or dark appearance of your device.")
            }

            Section {
                Toggle("Haptics", isOn: preferences.$hapticsEnabled)
                Toggle("Notifications", isOn: preferences.$notificationsEnabled)
            } header: {
                Text("Feedback")
            } footer: {
                Text("Notifications remind you about balances and new expenses in your groups.")
            }

            SyncStatusSection()

            Section("Free Forever") {
                Text("Splt has no ads, no limits and no subscription, now and later.")
            }

            Section("About") {
                LabeledContent("Version", value: AppInfo.versionDescription)
                LabeledContent("License") {
                    Text("MIT")
                }
                Link(destination: AppInfo.sourceCodeURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.selection, trigger: preferences.hapticsEnabled)
        .onChange(of: preferences.notificationsEnabled) { _, isOn in
            guard isOn else { return }
            Task {
                if await SyncRuntime.shared.requestNotificationAuthorization() == false {
                    preferences.notificationsEnabled = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}

#Preview("Large text") {
    NavigationStack { SettingsView() }
        .dynamicTypeSize(.accessibility2)
}
