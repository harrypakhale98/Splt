import SwiftUI

/// One export in the settings list: tap to prepare it, then share it. A failure says why and offers Retry.
struct GroupExportRow: View {
    let kind: GroupExportKind
    let state: GroupExportState
    let prepare: () -> Void

    var body: some View {
        switch state {
        case .idle:
            Button(action: prepare) {
                Label(title, systemImage: symbol)
            }
        case .preparing:
            HStack(spacing: 12) {
                ProgressView()
                Text("Preparing \(shortName)")
                    .foregroundStyle(Ink.secondary)
            }
            .accessibilityElement(children: .combine)
        case .ready(let url):
            ShareLink(item: url) {
                Label("Share \(shortName)", systemImage: "square.and.arrow.up")
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Ink.owe)
                Button("Retry", systemImage: "arrow.clockwise", action: prepare)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .csv: "Export as Spreadsheet (CSV)"
        case .pdf: "Export as PDF"
        case .json: "Export as JSON"
        }
    }

    private var shortName: String {
        switch kind {
        case .csv: String(localized: "CSV")
        case .pdf: String(localized: "PDF")
        case .json: String(localized: "JSON")
        }
    }

    private var symbol: String {
        switch kind {
        case .csv: "tablecells"
        case .pdf: "doc.richtext"
        case .json: "curlybraces"
        }
    }
}

#Preview {
    List {
        GroupExportRow(kind: .csv, state: .idle, prepare: {})
        GroupExportRow(kind: .pdf, state: .preparing, prepare: {})
        GroupExportRow(kind: .json, state: .failed("Splt couldn't prepare the export. Try again."), prepare: {})
    }
}
