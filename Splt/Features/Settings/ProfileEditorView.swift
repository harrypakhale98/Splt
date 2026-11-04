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
        ScrollView {
            VStack(spacing: 20) {
                avatar
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("Name", text: $profile.displayName, prompt: Text("Your Name"))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(commit)
                        .accessibilityIdentifier("profile.name")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
                note("Friends see this name in groups and when you invite them. It stays on your devices.")

                VStack(spacing: 0) {
                    ForEach(Array(AccountProfile.handleMethods.enumerated()), id: \.element) { index, method in
                        if index > 0 { Divider().padding(.leading, 56) }
                        HandleField(profile: profile, method: method)
                    }
                }
                .cardSurface()
                note("Optional. Added to reminders you send so friends know how to pay you. Splt never sends money.")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: commit)
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
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var avatar: some View {
        let name = profile.hasName ? profile.effectiveName : (summary.meName ?? profile.effectiveName)
        if let meID = summary.meID {
            AvatarView(name: name, id: meID, size: 96)
        } else {
            AvatarView(name: name, hue: PersonPalette.meIndex, size: 96)
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
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(method.handleTitle)
            TextField(method.handleTitle, text: $text, prompt: Text(method.handlePrompt))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(method == .zelle ? .emailAddress : .asciiCapable)
                .foregroundStyle(.secondary)
                .onChange(of: text) { profile.setHandle(text, for: method) }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .onAppear { text = profile.handle(for: method) }
    }
}

#Preview {
    NavigationStack {
        ProfileEditorView(profile: AccountProfile(defaults: UserDefaults(suiteName: "preview")!, deviceName: "Sam's iPhone"))
    }
}
