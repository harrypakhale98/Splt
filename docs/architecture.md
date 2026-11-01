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
- Conflicts resolve per field, last writer wins, and expenses are soft deleted so history is kept.
- Change notifications use CloudKit subscriptions, which cost nothing.

Sync sits behind a protocol. Builds without the iCloud entitlement use a no-op engine, so the app runs fully offline in the simulator and in CI.

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

Fetched from the free ECB-backed Frankfurter API, cached on the device, and always optional. A group can pin a fixed rate for a trip.

## Targets

| Target | Role |
| --- | --- |
| `Splt` | iOS app |
| `SpltTests` | Unit tests |
| `SpltUITests` | UI tests |
| `SpltKit/SpltCore` | Shared logic package |

Widgets, Shortcuts and share extensions are added as separate targets once the core is stable.
