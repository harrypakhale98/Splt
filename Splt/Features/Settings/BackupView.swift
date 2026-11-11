import SwiftUI

/// Where making a backup stands.
enum BackupFileState: Equatable, Sendable {
    case idle
    case preparing
    case ready(URL)
    case failed(String)
}

/// Makes one backup file and hands it to the share sheet, which also offers Save to Files.
@MainActor
@Observable
final class BackupModel {
    var includesPhotos = true {
        didSet { if oldValue != includesPhotos { state = .idle } }
    }
    private(set) var state: BackupFileState = .idle
    /// The file without photos, measured once the screen opens.
    private(set) var recordBytes: Int?
    private(set) var photoCount = 0
    private(set) var photoBytes = 0

    private let services: DataServices
    /// Where files are written. Tests point it somewhere else.
    @ObservationIgnored var directory = BackupFileJob.defaultDirectory

    init(services: DataServices) {
        self.services = services
    }

    /// Roughly how large the file will be. Photos grow by a third as text inside the file.
    var estimatedBytes: Int? {
        recordBytes.map { $0 + (includesPhotos ? photoBytes / 3 * 4 : 0) }
    }

    func measure() async {
        guard let contents = try? gather() else { return }
        photoCount = contents.photos.count
        photoBytes = contents.photoBytes
        recordBytes = await BackupFileJob.recordBytes(of: contents.document)
    }

    func prepare() async {
        if state == .preparing { return }
        state = .preparing
        do {
            let job = BackupFileJob(contents: try gather(), includesPhotos: includesPhotos, directory: directory)
            state = .ready(try await job.run())
        } catch {
            state = .failed(String(localized: "Couldn't make the backup. Check that your iPhone has free space, then try again."))
        }
    }

    private func gather() throws -> BackupWriter.Contents {
        try BackupWriter(context: services.environment.context)
            .contents(now: services.environment.now(), appVersion: AppInfo.versionDescription)
    }
}

/// Back Up Everything: one toggle, the size, and one action.
struct BackupView: View {
    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            BackupContent(services: services)
        } else {
            EmptyStateView.dataUnavailable
                .navigationTitle("Back Up")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BackupContent: View {
    @State private var model: BackupModel

    init(services: DataServices) {
        _model = State(initialValue: BackupModel(services: services))
    }

    var body: some View {
        @Bindable var model = model

        List {
            Section {
                RaisedRows {
                    Toggle("Include Photos", isOn: $model.includesPhotos)
                        .tint(Ink.switchOn)
                        .disabled(model.state == .preparing)
                    LabeledContent("Estimated Size") {
                        if let bytes = model.estimatedBytes {
                            Text(Int64(bytes), format: .byteCount(style: .file))
                                .monospacedDigit()
                        } else {
                            ProgressView()
                        }
                    }
                }
            } header: {
                SectionHeader("Backup")
            } footer: {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
            .paperSection()

            Section {
                action
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .paperBackground()
        .navigationTitle("Back Up")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.measure() }
    }

    private var footer: LocalizedStringKey {
        model.photoCount == 0
            ? "The backup holds every group, expense, payment and comment you can see. There are no receipt or group photos to include."
            : "The backup holds every group, expense, payment and comment you can see, and with Include Photos on, the receipt and group photos on this iPhone."
    }

    @ViewBuilder
    private var action: some View {
        switch model.state {
        case .idle:
            // the screen's one main action
            Button("Make Backup") { Task { await model.prepare() } }
                .buttonStyle(PrimaryButtonStyle())
        case .preparing:
            Button {} label: {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Making Backup…")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(true)
        case .ready(let url):
            ShareLink(item: url) {
                Text("Save or Share Backup…")
            }
            .buttonStyle(PrimaryButtonStyle())
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Ink.owe)
                Button("Try Again") { Task { await model.prepare() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}
