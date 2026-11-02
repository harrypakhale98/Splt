import SpltCore
import SwiftUI
import Testing
@testable import Splt

/// Draws the orbit at a few sizes to PNG files so the layout can be looked at. It does nothing unless
/// `SPLT_SHOTS_DIR` is set in the test environment.
@MainActor
@Suite("Orbit snapshots")
struct OrbitSnapshotTests {
    private func people(_ count: Int) -> [Person] {
        let names = ["Jamie Rivera", "Maya Chen", "Jonas Weber", "Priya Nair", "Diego Alvarez", "Hana Sato",
                     "Tom Becker", "Lena Ford", "Omar Haddad", "Ivy Park", "Noah Quinn", "Zoe Adler"]
        return (0..<count).map { index in
            Person(
                id: PersonID(rawValue: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!),
                name: names[index], kind: index == 0 ? .me : .friend
            )
        }
    }

    private func board(_ count: Int, simplified: Bool = true, settled: Bool = false) -> (OrbitBoard, [PersonID]) {
        let members = people(count)
        var debts: [Debt] = []
        var nets: [PersonID: Int64] = [:]
        if !settled {
            for (index, person) in members.enumerated().dropFirst() {
                let amount = Int64(1500 + index * 1900)
                debts.append(Debt(debtor: person.id, creditor: members[0].id, amount: usdAmount(amount)))
                nets[person.id] = -amount
                nets[members[0].id, default: 0] += amount
            }
            if !simplified, count > 3 {
                debts.append(Debt(debtor: members[2].id, creditor: members[3].id, amount: usdAmount(2200)))
            }
        }
        let board = OrbitBoard(
            members: members, me: members[0].id, nets: nets.mapValues(usdAmount), debts: debts, currencyCode: "USD"
        )
        return (board, members.map(\.id))
    }

    private func write<V: View>(_ view: V, named name: String, dark: Bool, size: DynamicTypeSize = .large) {
        guard let folder = ProcessInfo.processInfo.environment["SPLT_SHOTS_DIR"] else { return }
        let framed = view
            .padding(20)
            .frame(width: 402)
            .background(Color(.systemGroupedBackground))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, size)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let url = URL(fileURLWithPath: folder).appendingPathComponent("orbit-\(name)-\(dark ? "dark" : "light").png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? renderer.uiImage?.pngData()?.write(to: url)
    }

    @Test func drawsTheOrbitAtEverySize() {
        for dark in [false, true] {
            for count in [2, 3, 6, 9, 12] {
                let (board, ids) = board(count)
                write(
                    BalanceOrbitView(board: board, members: ids, onSettle: { _ in }),
                    named: "\(count)", dark: dark
                )
            }
            let (focused, ids) = board(6, simplified: false)
            write(
                BalanceOrbitView(board: focused, members: ids, initialFocus: .person(ids[1]), onSettle: { _ in }),
                named: "6-focus", dark: dark
            )
            let (settled, settledIDs) = board(5, settled: true)
            write(BalanceOrbitView(board: settled, members: settledIDs, onSettle: { _ in }), named: "settled", dark: dark)
        }
    }
}
