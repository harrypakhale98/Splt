import SpltCore
import SwiftUI

/// Reads a backup file, shows what it holds and what restoring it would do, and restores on confirm.
@MainActor
@Observable
final class RestoreBackupModel {
    enum Step: Equatable {
        case reading
        case failed(String)
        case ready(BackupRestorer.Plan)
        case restoring
        case done(BackupRestorer.Summary)
    }

    private(set) var step: Step = .reading
    @ObservationIgnored private var document: BackupDocument?
    private let restorer: BackupRestorer

    init(services: DataServices) {
        restorer = BackupRestorer(environment: services.environment)
    }

    init(restorer: BackupRestorer) {
        self.restorer = restorer
    }

    func load(_ url: URL) async {
        step = .reading
        do {
            let document = try await Task.detached(priority: .userInitiated) { try BackupDocument.read(url) }.value
            Self.removeInboxCopy(url)
            self.document = document
            step = .ready(try restorer.plan(for: document))
        } catch {
            Self.removeInboxCopy(url)
            step = .failed(((error as? BackupError) ?? .unreadable).message)
        }
    }

    func restore() {
        guard let document, case .ready = step else { return }
        step = .restoring
        do {
            step = .done(try restorer.restore(document))
            self.document = nil
        } catch {
            step = .failed(((error as? BackupError) ?? .saveFailed).message)
        }
    }

    /// A file opened from another app is copied into Documents/Inbox. Once read it is not needed there.
    private static func removeInboxCopy(_ url: URL) {
        let inbox = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory).standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(inbox + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// The restore flow in its own sheet.
struct RestoreBackupSheet: View {
    let file: OpenedBackup

    @Environment(\.dataServices) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let services {
                    RestoreBackupContent(file: file, services: services)
                } else {
                    EmptyStateView.dataUnavailable
                }
            }
            .navigationTitle("Restore from Backup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(Ink.paper)
    }
}

private struct RestoreBackupContent: View {
    let file: OpenedBackup

    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var model: RestoreBackupModel
    @State private var restoreCount = 0

    init(file: OpenedBackup, services: DataServices) {
        self.file = file
        _model = State(initialValue: RestoreBackupModel(services: services))
    }

    var body: some View {
        content
            .paperBackground()
            .task(id: file.id) { await model.load(file.url) }
            .haptic(.success, trigger: restoreCount)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .reading, .restoring:
            ProgressView(model.step == .reading ? "Reading Backup…" : "Restoring…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { cancel }
        case .failed(let message):
            ContentUnavailableView {
                Label("Can't Restore This File", systemImage: "doc.questionmark")
            } description: {
                Text(message)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        case .ready(let plan):
            planList(plan)
        case .done(let summary):
            doneList(summary)
        }
    }

    private var cancel: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { dismiss() }
        }
    }

    private func planList(_ plan: BackupRestorer.Plan) -> some View {
        List {
            Section {
                RaisedRows {
                    LabeledContent("Made", value: plan.createdAt.formatted(date: .long, time: .shortened))
                    count("Groups", plan.groups)
                    count("Expenses", plan.expenses)
                    count("Payments", plan.payments)
                    count("Photos", plan.photos)
                }
            } header: {
                SectionHeader("In the backup")
            }
            .paperSection()

            Section {
                RaisedRows {
                    if plan.groupsToRestore > 0 {
                        Text("^[\(plan.groupsToRestore) group](inflect: true) will be added as your own, in your iCloud. People in them who aren't you are added as new people, and can be claimed when they join.")
                    }
                    if !plan.groupsAlreadyHere.isEmpty {
                        Text("^[\(plan.groupsAlreadyHere.count) group was](inflect: true) already here and will be skipped: \(plan.groupsAlreadyHere.formatted(.list(type: .and)))")
                    }
                    Text("Nothing already on this iPhone is changed or removed.")
                }
                .font(.subheadline)
            } header: {
                SectionHeader("What happens")
            }
            .paperSection()
        }
        .listStyle(.plain)
        .toolbar {
            cancel
            ToolbarItem(placement: .confirmationAction) {
                Button("Restore") {
                    model.restore()
                    if case .done = model.step { restoreCount += 1 }
                }
                .disabled(!plan.canRestore)
            }
        }
    }

    private func doneList(_ summary: BackupRestorer.Summary) -> some View {
        List {
            Section {
                RaisedRows {
                    count("Groups Added", summary.groupsRestored)
                    count("Expenses", summary.expenses)
                    count("Payments", summary.payments)
                    count("People Added", summary.people)
                    count("Photos", summary.photos)
                }
            } header: {
                SectionHeader("Restored")
            } footer: {
                if summary.groupsAlreadyHere > 0 {
                    Text("^[\(summary.groupsAlreadyHere) group was](inflect: true) already here.")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                }
            }
            .paperSection()
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if let group = summary.firstGroup {
                        router.openedBackup = nil
                        router.open(.group(group.rawValue))
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }

    private func count(_ title: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(title) {
            Text(value, format: .number).monospacedDigit()
        }
    }
}
