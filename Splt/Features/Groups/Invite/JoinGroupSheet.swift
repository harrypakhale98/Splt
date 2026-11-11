import SpltCore
import SwiftUI

/// "Which one are you", right after joining from an invite made for someone added by name. Built like
/// Merge: the person the invite was for first, then anyone else still waiting, then someone new.
struct JoinGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: JoinGroupModel
    @State private var choice: Person?

    init(claim: JoinClaim, services: DataServices, merger: (any PlaceholderMerging)? = nil) {
        _model = State(initialValue: JoinGroupModel(claim: claim, services: services, merger: merger))
    }

    var body: some View {
        NavigationStack {
            List {
                if let invited = model.invited {
                    Section {
                        RaisedRows { row(invited, detail: model.invitedLine) }
                    } header: {
                        SectionHeader("Invited as")
                    }
                }
                Section {
                    RaisedRows {
                        ForEach(model.others) { row($0, detail: nil) }
                        Button {
                            dismiss()
                        } label: {
                            Label("Someone New", systemImage: "person.badge.plus")
                                .foregroundStyle(Ink.text)
                        }
                        .accessibilityIdentifier("join.someoneNew")
                    }
                } header: {
                    SectionHeader("Someone else")
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Ink.hairline)
            .paperBackground()
            .navigationTitle("Join \(model.groupName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .confirmationDialog(
                "Join as \(choice?.name ?? "")?", isPresented: choiceBinding, titleVisibility: .visible, presenting: choice
            ) { person in
                Button("Join as \(person.name)") { model.join(as: person) }
            } message: { person in
                Text("Everything added for \(person.name) becomes yours.")
            }
            .alert("Couldn't Join", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .onChange(of: model.didJoin) {
                if model.didJoin { dismiss() }
            }
            .task {
                // the person was already claimed, perhaps on another device: nothing to ask
                if model.isEmpty { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("join.sheet")
    }

    private func row(_ person: Person, detail: String?) -> some View {
        Button {
            choice = person
        } label: {
            HStack(spacing: 12) {
                AvatarView(person: person, size: 28)
                VStack(alignment: .leading) {
                    Text(person.name).foregroundStyle(Ink.text)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                    }
                }
            }
        }
    }

    private var choiceBinding: Binding<Bool> {
        Binding(get: { choice != nil }, set: { if !$0 { choice = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
