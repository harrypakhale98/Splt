import SpltCore
import SwiftUI

/// The welcome tour's pages, in order. Each hands something to the next: your name becomes your
/// avatar, and your avatar's color and your currency become your part of the sample split.
enum OnboardingPage: Int, CaseIterable {
    case welcome
    case profile
    case demo

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }
    var isLast: Bool { next == nil }
    /// The sample split is quick and is the point of the tour, so it has no Skip.
    var showsSkip: Bool { self != .demo }

    var identifier: String {
        switch self {
        case .welcome: "onboarding.page.welcome"
        case .profile: "onboarding.page.profile"
        case .demo: "onboarding.page.demo"
        }
    }
}

/// One edge for the whole tour, matching the cards and the rest of the app.
enum OnboardingLayout {
    static let margin = Depth.pageMargin
}

/// What Splt is, and a way in for someone who came from an invite.
struct OnboardingWelcomePage: View {
    var onInvite: (JoinInvite) -> Void = { _ in }
    @State private var notAnInvite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShareStrip(colors: (0..<5).map { PersonPalette.color(at: $0 * 2) }, height: 4)
                Text("Split bills with friends")
                    .font(Typeface.display)
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Add what you paid and see who owes whom.")
                    .font(.title3)
                    .foregroundStyle(Ink.secondary)
                inviteCard
                    .padding(.top, 8)
            }
            .padding(.horizontal, OnboardingLayout.margin)
            .padding(.top, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Someone who installed Splt from an invite copied it on the way. Apple's Paste button reads
    /// the clipboard only when tapped, so there is no "Allow Paste" prompt.
    private var inviteCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Got an invite?")
                    .foregroundStyle(Ink.text)
                Text(notAnInvite ? "That isn't a Splt invite. Copy the whole link and try again." : "Paste the link you were sent.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 8)
            PasteButton(payloadType: String.self) { strings in
                let invite = strings.lazy.compactMap { JoinInvite(text: $0) }.first
                Task { @MainActor in
                    if let invite {
                        notAnInvite = false
                        onInvite(invite)
                    } else {
                        notAnInvite = true
                    }
                }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            // the system draws its own white label, so the fill stays dark enough to read in both appearances
            .tint(Ink.whiteLabelFill)
            .accessibilityIdentifier("onboarding.paste")
        }
        .padding(Depth.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Your name and currency, with your avatar in your own color answering as you type.
struct OnboardingProfilePage: View {
    @Bindable var profile: AccountProfile
    let preferences: Preferences

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 24) {
                    // your color is fixed, not chosen: this is the first place you see it
                    AvatarView(name: profile.effectiveName, hue: PersonPalette.meIndex, size: 56)
                        .motion(Motion.quick, value: profile.effectiveName)
                        .accessibilityIdentifier("onboarding.avatar")
                    Text("Make it yours")
                        .font(Typeface.display)
                        .foregroundStyle(Ink.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your name is what friends see. You can change both later.")
                        .font(.title3)
                        .foregroundStyle(Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 48, leading: OnboardingLayout.margin, bottom: 16, trailing: OnboardingLayout.margin))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                RaisedRows {
                    TextField("Your Name", text: $profile.displayName, prompt: Text("Your Name"))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityIdentifier("onboarding.name")
                    NavigationLink {
                        CurrencyPickerView()
                    } label: {
                        LabeledContent(
                            "Default Currency",
                            value: CurrencyCatalog.name(for: preferences.defaultCurrencyCode)
                        )
                    }
                    .accessibilityIdentifier("onboarding.currency")
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// The real Split Bar on a sample dinner, with you in your color. Nothing here is saved, and dragging
/// here leaves the expense form's own first-drag hint for your first real expense.
struct OnboardingDemoPage: View {
    let demo: OnboardingDemoModel

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    /// As in the expense form: VoiceOver and the largest text sizes read the split as a list.
    private var showsList: Bool { voiceOver || typeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Try it")
                    .font(Typeface.display)
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                Text(showsList
                     ? "Say you paid for dinner with \(OnboardingDemoModel.friendName). Change who pays what below."
                     : "Say you paid for dinner with \(OnboardingDemoModel.friendName). Drag to split it.")
                    .font(.title3)
                    .foregroundStyle(Ink.secondary)
                HeroAmount(demo.total, showsSign: false)
                    .accessibilityIdentifier("onboarding.demo.amount")
                VStack(alignment: .leading, spacing: 12) {
                    split
                    friendShare
                }
                // room above the bar for the label that floats over a divider while it is held
                .padding(.top, showsList ? 0 : 20)
            }
            .padding(.horizontal, OnboardingLayout.margin)
            .padding(.top, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var split: some View {
        let data = demo.barData
        let members = [demo.me.id, demo.friend.id]
        if showsList {
            SplitShareList(data: data, members: members, currentPerson: demo.me.id, onStep: { person, increase in
                demo.step(person, increase: increase)
            }, hues: demo.hues)
            .accessibilityIdentifier("onboarding.demo.list")
        } else {
            SplitBarView(
                data: data, members: members, currentPerson: demo.me.id, stepHint: demo.stepDescription,
                onDrag: { divider, fraction in demo.drag(divider, toFraction: fraction) },
                onStep: { person, increase in demo.step(person, increase: increase) },
                // there is nothing to fine tune in a sample
                onTap: { _ in },
                hues: demo.hues,
                offersFineTune: false
            )
            .accessibilityIdentifier("onboarding.demo.bar")
        }
    }

    /// Sam's part in plain ink: green would say real money is coming to you, and this is a sample.
    private var friendShare: some View {
        let share = demo.friendShare
        return HStack(alignment: .firstTextBaseline) {
            Text("\(OnboardingDemoModel.friendName)'s share")
                .foregroundStyle(Ink.secondary)
            Spacer(minLength: 8)
            Text(MoneyFormatting.magnitudeString(share, locale: locale))
                .font(Typeface.figure)
                .foregroundStyle(Ink.text)
                .contentTransition(.numericText(value: Double(share.minorUnits)))
                .motion(Motion.quick, value: share)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.demo.share")
    }
}
