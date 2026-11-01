import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    EmptyStateView(
                        title: "Search Splt",
                        systemImage: "magnifyingglass",
                        description: "Find friends, groups and expenses."
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Friends, groups, expenses")
        }
    }
}

#Preview {
    SearchView()
}
