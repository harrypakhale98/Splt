import SwiftUI
import UniformTypeIdentifiers

/// The Backup section of Account: make a file of everything, or add back what one holds.
struct BackupSection: View {
    @Environment(Router.self) private var router
    @State private var showsPicker = false
    @State private var pickerFailed = false

    var body: some View {
        Section {
            RaisedRows {
                NavigationLink("Back Up Everything…") {
                    BackupView()
                }
                .accessibilityIdentifier("account.backup")
                Button("Restore from Backup…") {
                    showsPicker = true
                }
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("account.restore")
            }
        } header: {
            SectionHeader("Backup")
        } footer: {
            Text("A backup is a file you keep. Splt never uploads it anywhere.")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
        }
        .paperSection()
        .fileImporter(isPresented: $showsPicker, allowedContentTypes: [.spltBackup], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { router.openedBackup = OpenedBackup(url: url) }
            case .failure:
                pickerFailed = true
            }
        }
        .alert("Couldn't Open the File", isPresented: $pickerFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose a Splt backup file and try again.")
        }
    }
}
