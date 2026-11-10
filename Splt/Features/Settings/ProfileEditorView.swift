import SpltCore
import SwiftUI

/// Your name and the payment details that go into reminders you send.
struct ProfileEditorView: View {
    @Environment(\.dataServices) private var services
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: AccountProfile

    @State private var savedByDone = false
    @State private var errorMessage: String?
    @State private var summary = AccountSummary()
    @FocusState private var nameFocused: Bool

    var body: some View {
        List {
            Section {
                avatar
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                RaisedRows {
                    TextField("Name", text: $profile.displayName, prompt: Text("Your Name"))
                        .font(Typeface.heading)
                        .foregroundStyle(Ink.text)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit { commit() }
                        .accessibilityIdentifier("profile.name")
                }
            } header: {
                SectionHeader("Name")
            } footer: {
                note("Friends see this name in groups and when you invite them. It stays on your devices.")
            }
            .paperSection()

            Section {
                RaisedRows {
                    ForEach(AccountProfile.handleMethods, id: \.self) { method in
                        HandleField(profile: profile, method: method)
                    }
                }
            } footer: {
                note("Optional. Added to reminders you send so friends know how to pay you. Splt never sends money.")
            }
            .paperSection()
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .navigationTitle("Your Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if commit() {
                        savedByDone = true
                        dismiss()
                    }
                }
            }
        }
        // going back without Done still keeps what was typed
        .onDisappear { if !savedByDone { commit() } }
        .task { summary = AccountSummary.load(from: services, profile: profile) }
        .alert("Couldn't Save Name", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Ink.secondary)
    }

    @ViewBuilder
    private var avatar: some View {
        let name = profile.hasName ? profile.effectiveName : (summary.meName ?? profile.effectiveName)
        if let meID = summary.meID {
            AvatarView(name: name, id: meID, size: 56)
        } else {
            AvatarView(name: name, hue: PersonPalette.meIndex, size: 56)
        }
    }

    /// Saves while the screen is still up, so a failure can show its alert.
    @discardableResult
    private func commit() -> Bool {
        profile.save()
        guard let services else { return true }
        do {
            try profile.applyName(to: services.people)
            return true
        } catch {
            errorMessage = String(localized: "Your name couldn't be saved. Try again.")
            return false
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct HandleField: View {
    let profile: AccountProfile
    let method: SettleMethod

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var text: String

    init(profile: AccountProfile, method: SettleMethod) {
        self.profile = profile
        self.method = method
        _text = State(initialValue: profile.handle(for: method))
    }

    var body: some View {
        // at accessibility sizes the field goes under its label, so neither is cut short
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(method.handleTitle)
            TextField(method.handleTitle, text: $text, prompt: Text(method.handlePrompt))
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(method == .zelle ? .emailAddress : .asciiCapable)
                .foregroundStyle(Ink.secondary)
                .onChange(of: text) { profile.setHandle(text, for: method) }
                // picks up a handle changed elsewhere while this screen stays in the stack
                .onChange(of: profile.handle(for: method)) { _, saved in
                    if saved != text { text = saved }
                }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileEditorView(profile: AccountProfile(defaults: UserDefaults(suiteName: "preview")!, deviceName: "Sam's iPhone"))
    }
}
