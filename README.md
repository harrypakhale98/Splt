# Splt

Split costs with friends and groups. Free, with no ads, no limits and no subscription, now and later.

Splt is an iOS app built with SwiftUI and Apple frameworks only. Groups sync between people through iCloud, so there is no server to run and nothing to pay for. Smart features such as receipt scanning and quick entry run on the device, so your data stays with you.

## Principles

- Free forever. No paid tier, no expense caps, no ads.
- No accounts. Your Apple ID is your identity.
- Private by default. Nothing leaves your iCloud.
- Stock Apple design. Standard controls, system fonts, Dynamic Type, VoiceOver.

## Requirements

- Xcode 26 or later
- iOS 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you change `project.yml`

## Build

```sh
git clone https://github.com/harrypakhale98/Splt.git
cd Splt
open Splt.xcodeproj
```

Run the core tests without a simulator:

```sh
cd Packages/SpltKit && swift test
```

To try iCloud sync, set your own development team on the Splt target. The simulator and unsigned builds run fully offline.

## Layout

| Path | Purpose |
| --- | --- |
| `Splt/` | The app: views, view models, data, sync |
| `Packages/SpltKit/` | Pure Swift money, split and balance logic with tests |
| `docs/` | Architecture notes |

See [docs/architecture.md](docs/architecture.md) for details.

## License

MIT, see [LICENSE](LICENSE).
