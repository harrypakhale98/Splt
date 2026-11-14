import SwiftUI

/// How to send payments to Splt: a Wallet automation, bank texts and emails, screenshots and pasting.
/// Shortcuts has no way for an app to make the automation itself, so this shows the steps and then
/// confirms the first payment that arrives.
struct PaymentCaptureSetupView: View {
    var showsDone = false

    @Environment(\.dismiss) private var dismiss
    @State private var inbox = PaymentInbox.shared
    @State private var notificationsOn = Preferences().notificationsEnabled

    var body: some View {
        List {
            Section {
                Text("Splt can catch payments as you make them and keep them in To Split until you decide. They stay on this iPhone, and Splt never asks for your bank login.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, Depth.pageMargin)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .paperSection()

            Section {
                RaisedRows {
                    step(1, "Open Shortcuts, tap Automation, then the + button.")
                    step(2, "Choose Wallet, pick your cards and turn on Run Immediately. It's easy to miss.")
                    step(3, "Tap Next, then New Blank Automation, and add Splt's Log Payment action.")
                    step(4, "Set Merchant to Shortcut Input › Merchant and Amount to Shortcut Input › Amount.")
                    if let url = URL(string: "shortcuts://") {
                        Link(destination: url) {
                            Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("setup.openShortcuts")
                    }
                    status
                }
            } header: {
                SectionHeader("Apple Pay")
            } footer: {
                footnote("Not every till tells Wallet about a payment, and Mac and iPad payments aren't sent, so add anything missed by hand.")
            }
            .paperSection()

            if !notificationsOn {
                Section {
                    RaisedRows {
                        Button("Turn On Notifications") {
                            Task {
                                await NotificationAsk.turnOn()
                                notificationsOn = Preferences().notificationsEnabled
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                } header: {
                    SectionHeader("Reminders")
                } footer: {
                    footnote("Splt sends one list in the evening, and a nudge a while after a big or shared-looking payment. Never at the till.")
                }
                .paperSection()
            }

            Section {
                RaisedRows {
                    step(1, "In Shortcuts, make an automation for Message, or Email, from your bank.")
                    step(2, "Set Message Contains to a word your bank uses, like debited or spent, and turn on Run Immediately.")
                    step(3, "Add Splt's Log Payment from Text action and give it the message.")
                }
            } header: {
                SectionHeader("Bank Texts and Emails")
            } footer: {
                footnote("Splt skips one-time codes, offers and refunds, and never keeps the text, only the shop and the amount.")
            }
            .paperSection()

            Section {
                RaisedRows {
                    Label("Share a screenshot of a payment or receipt to Splt.", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44, alignment: .leading)
                    Label("Paste a bank text into Describe It when you add an expense.", systemImage: "doc.on.clipboard")
                        .frame(minHeight: 44, alignment: .leading)
                    Label("Say \"Split my last payment in Splt\" to Siri.", systemImage: "mic")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .font(.subheadline)
                .foregroundStyle(Ink.text)
            } header: {
                SectionHeader("Other Ways")
            }
            .paperSection()

            let muted = inbox.state.merchants.filter(\.value.isMuted).keys.sorted()
            if !muted.isEmpty {
                Section {
                    RaisedRows {
                        ForEach(muted, id: \.self) { key in
                            HStack {
                                Text(key.capitalized)
                                    .foregroundStyle(Ink.text)
                                Spacer()
                                Button("Unmute") { inbox.setMuted(false, merchantKey: key) }
                                    .buttonStyle(.borderless)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } header: {
                    SectionHeader("Muted")
                } footer: {
                    footnote("Payments from these places still arrive, under Everything Else, without a nudge.")
                }
                .paperSection()
            }
        }
        .listStyle(.plain)
        .paperBackground()
        .navigationTitle("Catch Payments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { inbox.reload() }
    }

    @ViewBuilder
    private var status: some View {
        if let last = inbox.state.lastWalletCaptureAt {
            Label("Working. Last payment caught \(last.formatted(.relative(presentation: .named))).", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Ink.owed)
                .frame(minHeight: 44, alignment: .leading)
        } else {
            Label("Waiting for your first tap. Pay with Apple Pay anywhere to try it.", systemImage: "wave.3.right")
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
                .frame(minHeight: 44, alignment: .leading)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Ink.text)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Ink.secondary)
            .padding(.horizontal, Depth.pageMargin)
    }
}
