# Contributing

Thanks for helping. Splt is a small project, so a short issue before a large change saves everyone time.

## Build

You need Xcode 26 or later. Open `Splt.xcodeproj`, pick the Splt scheme and an iPhone simulator. See the [README](README.md) for command line builds. Edit `project.yml` and run XcodeGen only if you add targets or settings. Source files in `Splt/`, `SpltTests/` and `SpltUITests/` are picked up without it.

## Test

```sh
cd Packages/SpltKit && swift test
```

Then run the Splt scheme on a simulator. New behavior needs tests, written with Swift Testing. Money logic goes in `Packages/SpltKit`, where it tests without a simulator.

## Style

- Swift 6 language mode with strict concurrency.
- Apple frameworks only. No third party packages, no analytics, no ads.
- Stock SwiftUI controls and system fonts and colors. Support Dynamic Type and VoiceOver.
- Money is an integer in minor units through `Money`. Never `Double` or `Decimal` for stored amounts.
- Keep files small and names clear. Comment only when the reason is not obvious, in short plain sentences.
- Put text people see in the string catalog.

## Commits and pull requests

- Subject in the imperative, at most 60 characters: "Fix rounding in percent splits".
- One change per commit, with a short body when the why is not obvious.
- Fill in the pull request template and keep the pull request focused.
- CI must pass.

## Privacy

Splt collects nothing and talks to no server of its own. A change that adds a network call, a tracker or a new stored data type needs a clear reason and an update to `docs/privacy.md` and the privacy manifest.
