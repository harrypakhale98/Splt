import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Splt", systemImage: "person.2", description: Text("Split costs with friends."))
                .navigationTitle("Splt")
        }
    }
}

#Preview {
    RootView()
}
