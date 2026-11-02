import SwiftUI

/// Your name and the payment details that go into reminders you send.
struct ProfileEditorView: View {
    @Environment(\.dataServices) private var services
    @Bindable var profile: AccountProfile

    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                AvatarView(name: profile.effectiveName, size: 96)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("Name", text: $profile.displayName, prompt: Text("Your Name"))
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit(commit)
            } header: {
                Text("Name")
            } footer: {
                Text("Friends see this name in groups and when you invite them. It stays on your devices.")
            }

            Section {
                ForEach(AccountProfile.handleMethods) { method in
                    HandleField(profile: profile, method: method)
                }
            } header: {
                Text("Payment Details")
            } footer: {
                Text("Optional. Added to reminders you send so friends know how to pay you. Splt never sends money.")
            }
        }
        .navigationTitle("Your Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: commit)
        .alert("Couldn't Save Name", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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
        LabeledContent(method.handleTitle) {
            TextField(method.handleTitle, text: $text, prompt: Text(method.handlePrompt))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(method == .zelle ? .emailAddress : .asciiCapable)
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
