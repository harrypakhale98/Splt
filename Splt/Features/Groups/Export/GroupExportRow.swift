import SwiftUI

/// The export in the settings list: one Export row whose menu picks the format. Each format that is
/// being prepared, is ready to share or failed gets a row of its own under it.
struct GroupExportRow: View {
    let state: (GroupExportKind) -> GroupExportState
    let prepare: (GroupExportKind) -> Void

    var body: some View {
        Menu {
            ForEach(GroupExportKind.allCases) { kind in
                Button(menuTitle(kind)) { prepare(kind) }
            }
        } label: {
            HStack {
                Text("Export")
                    .foregroundStyle(Ink.text)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(Ink.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        ForEach(GroupExportKind.allCases.filter { state($0) != .idle }) { kind in
            status(kind)
        }
    }

    @ViewBuilder
    private func status(_ kind: GroupExportKind) -> some View {
        switch state(kind) {
        case .idle:
            EmptyView()
        case .preparing:
            HStack(spacing: 12) {
                ProgressView()
                Text("Preparing \(shortName(kind))")
                    .foregroundStyle(Ink.secondary)
            }
            .accessibilityElement(children: .combine)
        case .ready(let url):
            ShareLink(item: url) {
                Label("Share \(shortName(kind))", systemImage: "square.and.arrow.up")
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Ink.owe)
                Button("Retry", systemImage: "arrow.clockwise") { prepare(kind) }
            }
        }
    }

    private func menuTitle(_ kind: GroupExportKind) -> LocalizedStringKey {
        switch kind {
        case .csv: "Spreadsheet (CSV)"
        case .pdf: "PDF"
        case .json: "JSON"
        }
    }

    private func shortName(_ kind: GroupExportKind) -> String {
        switch kind {
        case .csv: String(localized: "CSV")
        case .pdf: String(localized: "PDF")
        case .json: String(localized: "JSON")
        }
    }
}

#Preview {
    List {
        GroupExportRow(
            state: { kind in
                switch kind {
                case .csv: .idle
                case .pdf: .preparing
                case .json: .failed("Couldn't prepare the export. Try again.")
                }
            },
            prepare: { _ in }
        )
    }
}
