# Architecture

## Goals

1. Free to build, run and use forever. No paid backend, no paid SDK.
2. Feels like an app Apple would ship. Standard SwiftUI controls and Liquid Glass chrome.
3. Correct money math. Every amount is an integer in minor units.
4. Works offline first and syncs when it can.

## Layers

```
Views  ->  Stores (Observable)  ->  Repository  ->  SwiftData  <->  Sync (CKSyncEngine)
                      |
                      +-> SpltCore (pure logic, no UI, no storage)
                      +-> Intelligence (on-device models)
```

### SpltCore

A Swift package with no dependencies. It holds:

- `Money` and currency minor-unit rules
- Split strategies: equal, exact, percent, shares, adjustment, itemized
- A largest-remainder allocator so splits always add up to the total
- Balance calculation and debt simplification
- Parsing helpers that the app can unit test without a simulator

### Data

SwiftData is the local source of truth. A repository protocol hides it from the views so tests can use an in-memory store.

### Sync

Sync is built on `CKSyncEngine`.

- Each group is a record zone. Groups you create live in your private database.
- Inviting a friend shares the zone with `CKShare`. Accepted groups appear in the shared database.
- People without the app are placeholders inside a group. They can be claimed later when they join.
- Conflicts resolve per record, last writer wins, so concurrent edits to one record can lose a change. Expenses are soft deleted so history is kept.
- Change notifications use CloudKit subscriptions, which cost nothing.

`Splt/Data/Sync` holds the data side of sync: change tracking, the merge policy and the payloads. `Splt/Sync` holds the transport: the engine, CloudKit and sharing.

Sync sits behind a protocol. Builds without the iCloud entitlement use a no-op engine, so the app runs fully offline in the simulator and in CI.

### Backup and spending

Backup lives in `Splt/Data/Backup` and `Splt/Features/Settings`. It writes everything to one file and restores it later. Spending lives in `Splt/Features/Spending`. It charts your share over the last 12 months, and a group has its own Spending tab.

### Intelligence

Everything runs on the device.

| Feature | Framework |
| --- | --- |
| Quick add ("dinner 60 with Sam and Priya") | Foundation Models |
| Receipt scanning and line items | VisionKit and Vision |
| Category suggestions | Foundation Models, Natural Language |
| Voice entry | Speech |
| Siri and Shortcuts | App Intents |
| Search in Spotlight | Core Spotlight |
| Comment translation | Translation |

Each feature degrades quietly when the model is unavailable.

### Exchange rates

Fetched from the free ECB-backed Frankfurter API, cached on the device, and always optional. A group can pin a fixed rate for a trip, typed in by hand, and a pinned rate always wins.

## Targets

| Target | Role |
| --- | --- |
| `Splt` | iOS app |
| `SpltTests` | Unit tests |
| `SpltUITests` | UI tests |
| `SpltWidgets` | Lock Screen To Split count, Control Center button, trip Live Activity |
| `SpltShare` | Share extension that reads a payment from a screenshot or text |
| `SpltKit/SpltCore` | Shared logic package |

Siri and Shortcuts work through App Intents inside the app target.

### To Split

Payments caught by Shortcuts automations (Wallet, Message, Email), the share extension or Siri wait in To Split, at the top of Activity. Everything lives in `Shared/Inbox`, a JSON file in the `group.com.harrypakhale.splt` app group that the app and both extensions read and write through `NSFileCoordinator`. It never syncs. `LogPaymentIntent` runs without Face ID, because Wallet runs it at the checkout, often on a locked phone, and it only adds to the inbox. The app (`Splt/Features/Inbox`) decides how loudly to ask about each payment, which group it goes to, when to nudge, the evening summary, and the trip wrap-up and Live Activity.
