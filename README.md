# Splt

[![CI](https://github.com/harrypakhale98/Splt/actions/workflows/ci.yml/badge.svg)](https://github.com/harrypakhale98/Splt/actions/workflows/ci.yml)

Split costs with friends and groups on iPhone.

Splt is free forever. No ads, no accounts, no limits and no subscription. Groups sync through your own iCloud, and the smart features run on the device. There is no Splt server.

<table>
  <tr>
    <td><img src="docs/images/groups-dark.png" width="180" alt="The Groups tab in dark mode, showing your overall balance and a plain list of groups"></td>
    <td><img src="docs/images/balance-orbit.png" width="180" alt="The balance orbit for a trip group, with thin colored ribbons between six people"></td>
    <td><img src="docs/images/split-bar.png" width="180" alt="The add expense sheet with an amount, the people in the expense and the split bar"></td>
    <td><img src="docs/images/settle-up.png" width="180" alt="The settle up sheet with one total and a plain list of who pays whom"></td>
  </tr>
  <tr>
    <td align="center">Groups</td>
    <td align="center">Balance orbit</td>
    <td align="center">Split bar</td>
    <td align="center">Settle up</td>
  </tr>
</table>

## What it does

- Groups and one to one balances, with debts simplified to the fewest payments.
- Six ways to split: equally, exact amounts, percentages, shares, adjustments and by item.
- A balance orbit that draws who owes whom, and a split bar you drag to set the shares.
- Any currency per expense, and recurring expenses.
- Quick add from a sentence, by typing or by voice, and receipt scanning. Receipt photos sync through iCloud, and each person can pick their own items.
- Settle up in full or in part. Splt never moves money.
- Reminders you share as a message, and a balance link that opens in any browser for friends without an iPhone.
- Spending charts for your share over the last 12 months, and a default split and a cover photo for each group.
- Invites by link or QR code, and export as a spreadsheet (CSV), PDF or JSON.
- Import from a Splitwise export, and back up everything to a file you can restore.
- A light, dark or system appearance switch, and a full edit history on each expense.

## Build

You need Xcode 26 or later and iOS 26 or later.

```sh
git clone https://github.com/harrypakhale98/Splt.git
cd Splt
open Splt.xcodeproj
```

Pick the Splt scheme and an iPhone simulator, then run. The simulator works fully offline, without sync. To sync through iCloud on a real device, follow [docs/sync.md](docs/sync.md).

## Tests

The money, split and balance logic lives in a Swift package and tests without a simulator:

```sh
cd Packages/SpltKit && swift test
```

The app tests run from the Splt scheme on a simulator.

## More

- [Website](https://harrypakhale98.github.io/Splt/), [support](https://harrypakhale98.github.io/Splt/support) and [privacy](https://harrypakhale98.github.io/Splt/privacy)
- [How the app is built](docs/architecture.md) and [the design rules](docs/design.md)
- To report a security problem, see [SECURITY.md](SECURITY.md)

## License

Copyright (c) 2026 Hardik Pakhale. All rights reserved. The source is public so you can read it, but it is not open source: you may not copy, modify, redistribute or build another app from it. See [LICENSE](LICENSE).
