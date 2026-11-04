import Foundation
import Observation
import SpltCore

/// Prepares a group for sharing and holds the result for the invite sheet.
///
///     .sheet(item: $model.prepared) { CloudSharingView(groupShare: $0.groupShare) }
@MainActor
@Observable
final class GroupSharingModel {
    struct Prepared: Identifiable {
        let id = UUID()
        let groupShare: GroupShare
    }

    enum Phase: Equatable {
        case idle
        case preparing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var prepared: Prepared?

    @ObservationIgnored private let engine: any SyncEngine

    init(engine: any SyncEngine) {
        self.engine = engine
    }

    func prepare(group: GroupID) async {
        phase = .preparing
        do {
            prepared = Prepared(groupShare: try await engine.share(group: group))
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
    }
}
