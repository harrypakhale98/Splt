import SpltCore
import SwiftUI

/// Pick the person a placeholder really is. Everything shared moves over to them.
struct MergeFriendView: View {
    let placeholder: Person
    let services: DataServices
    let merger: any PlaceholderMerging
    var onMerged: (Person) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: MergeFriendModel
    @State private var choice: Person?

    init(placeholder: Person, services: DataServices, merger: any PlaceholderMerging, onMerged: @escaping (Person) -> Void) {
        self.placeholder = placeholder
        self.services = services
        self.merger = merger
        self.onMerged = onMerged
        _model = State(initialValue: MergeFriendModel(placeholder: placeholder, services: services, merger: merger))
    }

    var body: some View {
        NavigationStack {
            List {
                if !model.suggestions.isEmpty {
                    Section {
                        RaisedRows { rows(model.suggestions) }
                    } header: {
                        SectionHeader("Possible matches")
                    }
                }
                if !model.others.isEmpty {
                    Section {
                        RaisedRows { rows(model.others) }
                    } header: {
                        SectionHeader("Everyone else")
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Ink.hairline)
            .paperBackground()
            .overlay {
                if model.suggestions.isEmpty, model.others.isEmpty {
                    EmptyStateView(
                        title: "Nobody to merge with",
                        systemImage: "person.2",
                        description: "Add the person's real name as a friend first."
                    )
                }
            }
            .navigationTitle("Merge \(placeholder.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .confirmationDialog(
                "Merge \(placeholder.name)?", isPresented: choiceBinding, titleVisibility: .visible, presenting: choice
            ) { target in
                Button("Merge into \(target.name)", role: .destructive) { model.merge(into: target) }
            } message: { target in
                Text("Everything shared with \(placeholder.name) moves to \(target.name). \(placeholder.name) is removed.")
            }
            .alert("Couldn't Merge", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .onChange(of: model.didMerge) {
                if let target = model.didMerge {
                    dismiss()
                    onMerged(target)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func rows(_ people: [Person]) -> some View {
        ForEach(people) { person in
            Button {
                choice = person
            } label: {
                HStack(spacing: 12) {
                    AvatarView(person: person, size: 28)
                    Text(person.name).foregroundStyle(Ink.text)
                    Spacer()
                    if person.isPlaceholder {
                        Text("Not on Splt yet")
                            .font(.footnote)
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
