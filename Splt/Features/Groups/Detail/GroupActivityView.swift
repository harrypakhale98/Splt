import SpltCore
import SwiftUI

/// What has happened in the group, newest first.
struct GroupActivityView: View {
    let entries: [ActivityEntry]
    let text: GroupActivityText

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(text.sentence(for: entry))
                Text(entry.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Ink.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .overlay {
            if entries.isEmpty {
                EmptyStateView(
                    title: "No Activity Yet",
                    systemImage: "list.bullet.rectangle",
                    description: "Expenses, payments and changes in this group show up here."
                )
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.kind == .trip }) ?? nil
    let model = trip.map { GroupDetailViewModel(groupID: $0.id, services: services) }
    NavigationStack {
        GroupActivityView(entries: model?.activity ?? [], text: model?.activityText ?? GroupActivityText(names: [:]))
    }
}
#endif
