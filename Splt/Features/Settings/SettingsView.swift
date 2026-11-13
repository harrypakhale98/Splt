import SwiftUI
import UserNotifications

/// The preference, sync, import, backup and about sections of the Account screen.
struct SettingsSections: View {
    @Environment(Router.self) private var router
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationsBlocked = false
    @State private var lockKind = BiometricKind.faceID
    @State private var lockAvailable = true
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
                Picker("Appearance", selection: preferences.$appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Ink.secondary)
                Toggle("Haptics", isOn: preferences.$hapticsEnabled)
                    .tint(Ink.switchOn)
                Toggle("Notifications", isOn: preferences.$notificationsEnabled)
                    .tint(Ink.switchOn)
                    .task(id: preferences.notificationsEnabled) { await checkNotifications() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            Task { await checkNotifications() }
                            refreshLock()
                        }
                    }
                Toggle("Require \(lockKind.name)", isOn: lockBinding)
                    .tint(Ink.switchOn)
                    // a phone without a passcode can't lock anything, but one already on can still be turned off
                    .disabled(!lockAvailable && !preferences.biometricLockEnabled)
                    .accessibilityIdentifier("account.biometricLock")
                    .onAppear(perform: refreshLock)
            }
        } header: {
            SectionHeader("Preferences")
        } footer: {
            VStack(alignment: .leading, spacing: 0) {
                if notificationsBlocked {
                    // turning the toggle on can't work until notifications are allowed in the Settings app
                    Text("Notifications are turned off in the Settings app.")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Link("Open Settings", destination: url)
                            .font(.footnote)
                            .foregroundStyle(Ink.text)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
                if !lockAvailable {
                    Text("Set a passcode on your iPhone to lock Splt with \(lockKind.name).")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                } else if preferences.biometricLockEnabled {
                    Text("Splt asks for \(lockKind.name) when you open it, and again if you have been away for more than \(Int(AppLock.gracePeriod)) seconds.")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                }
            }
        }
        .paperSection()

        SyncStatusSection()

        Section {
            RaisedRows {
                NavigationLink("Import from Splitwise") {
                    SplitwiseImportView()
                }
            }
        } header: {
            SectionHeader("Import")
        }

        BackupSection()

        Section {
            RaisedRows {
                LabeledContent("Version", value: AppInfo.versionDescription)
                LabeledContent("License") {
                    Text("All rights reserved")
                }
                Link("Source Code", destination: AppInfo.sourceCodeURL)
                    .foregroundStyle(Ink.text)
                Button("Show Welcome Tour") {
                    router.showWelcomeTour()
                }
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("account.welcomeTour")
            }
        } header: {
            SectionHeader("About")
        }
    }

    /// Turning it on asks for Face ID first, so the lock is never on without a way to open it.
    private var lockBinding: Binding<Bool> {
        Binding(
            get: { preferences.biometricLockEnabled },
            set: { isOn in
                guard isOn else {
                    preferences.biometricLockEnabled = false
                    return
                }
                Task {
                    if await lock.confirmEnabling() { preferences.biometricLockEnabled = true }
                }
            }
        )
    }

    private func refreshLock() {
        lockKind = lock.kind
        lockAvailable = lock.isAvailable
    }

    private func checkNotifications() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsBlocked = status == .denied
    }
}

extension View {
    /// Keeps a List section's header and footer on the paper. In a sheet they default to a lighter shade.
    func paperSection() -> some View {
        listRowBackground(Ink.paper)
            .listSectionSeparator(.hidden)
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
                guard isOn else {
                    // reminders scheduled while it was on would still arrive
                    Task { await ReminderScheduler().cancelAll() }
                    return
                }
                Task {
                    if await SyncRuntime.shared.requestNotificationAuthorization() == false {
                        preferences.notificationsEnabled = false
                    }
                }
            }
    }
}

