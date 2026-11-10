import SpltCore
import SwiftUI

/// Your name and the payment details that go into reminders you send.
struct ProfileEditorView: View {
    @Environment(\.dataServices) private var services
    @Bindable var profile: AccountProfile

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
                    TextField("Name", text: $profile.displayName, prompt: Text("Your name"))
                        .font(Typeface.heading)
                        .foregroundStyle(Ink.text)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(commit)
                        .accessibilityIdentifier("profile.name")
                }
            } header: {
                SectionHeader("Name")
            } footer: {
                note("Friends see this name in groups and when you invite them. It stays on your devices.")
            }
            // a section header or footer in a sheet defaults to a lighter shade than the paper behind it
            .listRowBackground(Ink.paper)
            .listSectionSeparator(.hidden)

            Section {
                RaisedRows {
                    ForEach(AccountProfile.handleMethods, id: \.self) { method in
                        HandleField(profile: profile, method: method)
                    }
                }
            } footer: {
                note("Optional. Added to reminders you send so friends know how to pay you. Splt never sends money.")
            }
            .listRowBackground(Ink.paper)
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .navigationTitle("Your Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: commit)
        .task { summary = AccountSummary.load(from: services) }
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

    private func commit() {
        profile.save()
        guard let services else { return }
        do {
            try profile.applyName(to: services.people)
        } catch {
            errorMessage = String(localized: "Something went wrong. Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct HandleField: View {
    let profile: AccountProfile
    let method: SettleMethod

    @State private var text = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: method.symbol)
                .font(.title3)
                .foregroundStyle(Ink.text)
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(method.handleTitle)
            TextField(method.handleTitle, text: $text, prompt: Text(method.handlePrompt))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(method == .zelle ? .emailAddress : .asciiCapable)
                .foregroundStyle(Ink.secondary)
                .onChange(of: text) { profile.setHandle(text, for: method) }
        }
        .onAppear { text = profile.handle(for: method) }
    }
}

#Preview {
    NavigationStack {
        ProfileEditorView(profile: AccountProfile(defaults: UserDefaults(suiteName: "preview")!, deviceName: "Sam's iPhone"))
    }
}
