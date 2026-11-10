# Sync

Splt syncs through your own iCloud with `CKSyncEngine`. There is no server to run and nothing to pay for: storage counts against each person's iCloud quota and CloudKit is free for apps.

Builds without the iCloud entitlement (the simulator, previews, tests, unsigned CI builds) use a no-op engine and run fully offline.

## Turn it on with your own team

1. Open `Splt.xcodeproj`, select the `Splt` target, Signing & Capabilities, and pick your team.
2. Change the bundle identifier to one you own, for example `com.yourname.splt`.
3. Open `Splt/Sync/Splt.entitlements` and change the container to `iCloud.` plus your bundle identifier. The app reads the container name from the signed entitlements, so this is the only place to change.
4. Build to a real device that is signed in to iCloud. Xcode creates the container and the push entitlement for you.

If you regenerate the project with XcodeGen, `project.yml` already points at the entitlements file.

## Deploy the schema before shipping

CloudKit creates record types on the fly in the Development environment, but TestFlight and App Store builds use Production, which has no types until you deploy them.

1. Open the CloudKit Dashboard, choose the container and stay in Development.
2. Choose Import Schema and pick `Config/CloudKitSchema.ckdb`. It holds every record type and every field the app can write, including the ones it only sets sometimes. Running the app once is not enough, because Development only learns a field the first time a value is saved in it.
3. Under Record Types, check that `Person`, `Group`, `Expense`, `Payment`, `Comment`, `Activity` and `RecurringExpense` are there.
4. Choose Deploy Schema Changes and confirm, then switch to Production and check the same types.

When a release adds a field to `RecordSchema.swift`, add it to `Config/CloudKitSchema.ckdb` too (a test fails until you do), then import and deploy again before the release ships. Deploying only adds, so it is safe to repeat.

No indexes are needed: the app never queries, it only reads zone changes.

## How it works

- Each group is one record zone. Groups you create live in your private database.
- People are copied into every group zone that mentions them, so each group is self contained.
- Local edits mark records dirty in the data store. The sync layer turns those into uploads and clears the flag when the server accepts them, so a failed upload is never forgotten.
- A change made on two devices at once is merged field by field by the data layer's merge policy: the later edit wins, a delete beats an older edit, and an undo beats the delete. Expenses and payments are soft deleted so history stays.
- Your identity is derived from your iCloud account, so all your devices are the same person in every group.
- Silent pushes from CloudKit wake the app to fetch changes. With notifications turned on in Settings, a change from a friend that arrives in the background becomes a local notification such as "Sam added Dinner in Lisbon". No server is involved.

## Sharing

1. In a group, choose Invite. The app creates a zone wide `CKShare` with no public access and shows the system invite sheet. Invitees get read and write access.
2. A friend opens the link. The system hands the app a share invitation, the app accepts it and the group appears in their list. They are added to the member list automatically.
3. People you added by name before they joined are placeholders. When the real person joins, claim the placeholder: every expense, payment and comment that mentioned the placeholder is rewritten to the real person.
4. A friend can leave a group from the invite sheet or the group's menu. The owner can stop sharing, which keeps the group on the owner's devices.

## Known limits

- Sharing and push only work on real devices signed in to iCloud. The simulator cannot be used to test them.
- Everyone needs an Apple ID and iCloud turned on. People without it can still be placeholders.
- Claiming a placeholder is refused when the placeholder and the real person appear together in one expense, because their shares would need merging by hand.
- Receipt photos stay on the device that scanned them. Only the file name syncs.
- After switching iCloud accounts, groups already on the device stay as local copies and are not uploaded to the new account.
- A device that stays offline for a very long time may have to refetch everything. A comment or person deleted elsewhere in the meantime can come back until it is deleted again.
- Deleting a shared group as its owner removes it for everyone.
- A full iCloud storage stops uploads for that person. Changes stay on the device and sync once space is available.
