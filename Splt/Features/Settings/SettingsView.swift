import SwiftUI

/// The preference, sync, import and about sections. They sit on the Account screen, and
/// `SettingsView` shows the same sections on their own when a route asks for settings.
struct SettingsSections: View {
    private let preferences = Preferences()

    var body: some View {
        Section {
            NavigationLink {
                CurrencyPickerView()
            } label: {
                LabeledContent(
                    "Default Currency",
                    value: CurrencyCatalog.name(for: preferences.defaultCurrencyCode)
                )
            }
        } header: {
            Text("General")
        } footer: {
            Text("New groups start with this currency.")
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

        Section {
            NavigationLink {
                SplitwiseImportView()
            } label: {
                Label("Import from Splitwise", systemImage: "square.and.arrow.down")
            }
        }

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
}

extension View {
    /// Plays feedback for toggles and asks for notification permission when it is turned on.
    func settingsBehavior() -> some View {
        modifier(SettingsBehavior())
    }
}

private struct SettingsBehavior: ViewModifier {
    private let preferences = Preferences()

    func body(content: Content) -> some View {
        content
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

struct SettingsView: View {
    var body: some View {
        Form {
            SettingsSections()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .settingsBehavior()
    }
}

#Preview {
    NavigationStack { SettingsView() }
}

#Preview("Large text") {
    NavigationStack { SettingsView() }
        .dynamicTypeSize(.accessibility2)
}
