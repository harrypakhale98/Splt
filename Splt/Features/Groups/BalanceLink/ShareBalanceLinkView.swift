import SpltCore
import SwiftUI

/// Shares a group's balances as a web link, for a friend without an iPhone. The numbers travel
/// inside the link, so nothing is uploaded. Opened from the group's share menu.
struct ShareBalanceLinkView: View {
    let group: SplitGroup
    let me: PersonID?
    let people: [PersonID: Person]
    let expenses: [Expense]
    let balances: GroupBalances?

    @Environment(\.dismiss) private var dismiss
    @State private var includesExpenses = true
    @State private var allowsReplies = true
    /// The moment the sheet opened: the link is a snapshot of it.
    @State private var now = Date()
    /// The code a reply sends back, which this phone remembers. Made when the sheet opens.
    @State private var replyToken: String?

    /// The link, or nil when the group doesn't fit in one.
    private var link: URL? {
        try? BalanceLink.url(for: BalanceSnapshot(
            group: group, me: me, people: people, expenses: expenses, balances: balances,
            includesExpenses: includesExpenses, now: now,
            replyToken: allowsReplies ? replyToken : nil
        ))
    }

    var body: some View {
        let link = link
        NavigationStack {
            List {
                Section {
                    RaisedRows {
                        preview
                    }
                }
                .raisedSection()
                Section {
                    RaisedRows {
                        HStack {
                            Text("Who pays whom")
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(Ink.secondary)
                                .accessibilityLabel("Always included")
                        }
                        .accessibilityElement(children: .combine)
                        Toggle("Recent Expenses", isOn: $includesExpenses)
                            .tint(Ink.switchOn)
                        Toggle("Let Them Send Expenses Back", isOn: $allowsReplies)
                            .tint(Ink.switchOn)
                            .accessibilityIdentifier("balanceLink.replies")
                    }
                } footer: {
                    Text(footer(fits: link != nil))
                        .padding(.horizontal, Depth.pageMargin + 4)
                }
                .raisedSection()
            }
            .paperBackground()
            .navigationTitle("Share as a Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .close) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if let link {
                        ShareLink(
                            item: link,
                            subject: Text("\(group.name) balances"),
                            message: Text("What everyone owes in \(group.name), from Splt.")
                        ) {
                            Text("Share Link")
                        }
                    } else {
                        Button("Share Link") {}
                            .disabled(true)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Depth.pageMargin + 4)
                .padding(.bottom, 8)
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard replyToken == nil else { return }
            replyToken = BalanceReplyStore().token(
                for: group.id,
                people: BalanceSnapshot.memberOrder(group: group, expenses: expenses, balances: balances)
            )
        }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            BrandDiscs()
                .frame(width: 32, height: 32)
                .background(Ink.paper, in: .rect(cornerRadius: Depth.thumbnailRadius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(group.name) · balances")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Opens in any browser, as of \(now.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func footer(fits: Bool) -> LocalizedStringKey {
        if fits, allowsReplies {
            "The numbers travel inside the link, so nothing is uploaded. It's a snapshot and won't change after you send it. Anyone with the link can see these names and amounts, and can send you an expense or a payment as a link, which you check on this iPhone before it's added."
        } else if fits {
            "The numbers travel inside the link, so nothing is uploaded. It's a snapshot and won't change after you send it. Anyone with the link can see these names and amounts."
        } else {
            "This group has too many people to fit in a link."
        }
    }
}

/// The app icon's two overlapping discs, coral and teal, small.
private struct BrandDiscs: View {
    var body: some View {
        HStack(spacing: -4) {
            Circle().fill(Color(red: 0xD9 / 255, green: 0x69 / 255, blue: 0x4F / 255))
            Circle().fill(Color(red: 0x3D / 255, green: 0x8C / 255, blue: 0x86 / 255)).opacity(0.9)
        }
        .frame(width: 22, height: 13)
    }
}

#Preview {
    let me = Person(name: "Maya", kind: .me)
    let leo = Person(name: "Leo")
    let group = SplitGroup(name: "Lisbon trip", currencyCode: "EUR", memberIDs: [me.id, leo.id])
    return Color.clear.sheet(isPresented: .constant(true)) {
        ShareBalanceLinkView(group: group, me: me.id, people: [me.id: me, leo.id: leo], expenses: [], balances: nil)
    }
}
