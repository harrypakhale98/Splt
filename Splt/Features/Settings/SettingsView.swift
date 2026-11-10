import SwiftUI

/// The preference, sync, import and about sections. They sit on the Account screen, and
/// `SettingsView` shows the same sections on their own when a route asks for settings.
struct SettingsSections: View {
    @Environment(Router.self) private var router
    private let preferences = Preferences()

    var body: some View {
        Section {
            RaisedRows {
                NavigationLink {
                    CurrencyPickerView()
                } label: {
                    LabeledContent(
                        "Default Currency",
                        value: CurrencyCatalog.name(for: preferences.defaultCurrencyCode)
                    )
                }
                Toggle("Haptics", isOn: preferences.$hapticsEnabled)
                Toggle("Notifications", isOn: preferences.$notificationsEnabled)
            }
        }

        SyncStatusSection()

        Section {
            RaisedRows {
                NavigationLink("Import from Splitwise") {
                    SplitwiseImportView()
                }
                Button("Show Welcome Tour") {
                    router.showWelcomeTour()
                }
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("account.welcomeTour")
            }
        }

        Section {
            RaisedRows {
                LabeledContent("Version", value: AppInfo.versionDescription)
                LabeledContent("License") {
                    Text("MIT")
                }
                Link("Source Code", destination: AppInfo.sourceCodeURL)
                    .foregroundStyle(Ink.text)
            }
        } header: {
            SectionHeader("About")
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
        List {
            SettingsSections()
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .settingsBehavior()
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(Router())
}

#Preview("Large text") {
    NavigationStack { SettingsView() }
        .environment(Router())
        .dynamicTypeSize(.accessibility2)
}
