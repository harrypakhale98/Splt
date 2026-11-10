# Sync

Splt syncs through your own iCloud with `CKSyncEngine`. There is no server to run and nothing to pay for: a group is stored in the iCloud of the person who created it and counts against their storage, also for what the people they shared it with add, and CloudKit is free for apps.

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
- People are copied into every group zone that mentions them, so each group is self contained. Email addresses and phone numbers from Contacts stay on the device and are not in the copy.
- Local edits mark records dirty in the data store. The sync layer turns those into uploads and clears the flag when the server accepts them, so a failed upload is never forgotten.
- When a record changes on two devices at once, the data layer's merge policy keeps one whole version: the later edit wins, a delete beats an older edit, and an undo beats the delete. Changes are not merged field by field, so the other edit to that record is lost. Expenses and payments are soft deleted so history stays.
- Your identity is derived from your iCloud account, so all your devices are the same person in every group.
- Silent pushes from CloudKit wake the app to fetch changes. With notifications turned on in Settings, a change from a friend that arrives in the background becomes a local notification such as "Sam added Dinner in Lisbon". No server is involved.

## Sharing

1. In a group's settings, choose Invite with iCloud. The app creates a zone wide `CKShare` with no public access and shows the system invite sheet. Invitees get read and write access.
2. Or choose Link or QR Code. The share is then open to anyone who has the link, with read and write access, and the app shows the link and a code to scan. The owner can close it again in the invite sheet, under who can join. CloudKit then removes everyone who joined through the link, so the group disappears from their devices; people invited by name stay. Once closed, the app asks before it opens the share again.
3. A friend you invited opens the link they received. The system hands the app a share invitation, the app accepts it and the group appears in their list. They are added to the member list automatically.
4. People you added by name before they joined are placeholders. When the real person joins, claim the placeholder: every expense, payment and comment that mentioned the placeholder is rewritten to the real person.
5. A friend leaves a group with Leave Group in the group's settings. Their removal from the member list reaches the others first, and if they are offline it is sent once they are back. Then the app deletes the group's share record from their shared database, which is how CloudKit has a participant leave. If CloudKit refuses that, the app gives up the zone instead, as version 1.0.0 did. The system invite sheet is only shown to the person who shared the group, because its Remove Me option would leave the share without leaving the member list.
6. The person who shared a group cannot leave it, because it lives in their iCloud and CloudKit cannot hand it to someone else. They can stop sharing from the invite sheet, which keeps the group on their own devices and removes it from everyone else's, or delete the group, which removes it for everyone.

## What a group member can do

CloudKit gives everyone in a shared zone write access to the whole zone, and any app can write to it, not only Splt. So every record that arrives is treated as untrusted.

- A record only counts inside its own group: its group id must be the zone it came from, and a record cannot take over or delete one from another group.
- A zone with the name of a group on this device but another owner is ignored, so edits never go to it.
- Amounts larger than the app itself allows, and modified dates more than ten years ahead, are refused.
- Each device makes a recurring expense's occurrences itself, so a template only catches up on the last year, at most 100 expenses each time the app opens.
- A person record cannot delete anyone, and only your own devices can rename you here.
- A file name on a synced expense can only ever point at a receipt photo.

Inside one group, members are trusted: anyone can edit or delete its expenses, payments and members. They can also change the name of anyone they share a group with, on the devices of everyone else in that group, because a person record has no owner. Change this only with a real test across accounts: other people's devices upload copies of a person, so the last writer is often not that person.

## Check it on real devices

The tests run sync against stand-ins for CloudKit, and the simulator has no iCloud. Before a release that touches `Splt/Sync`, walk through this with two iPhones on two iCloud accounts, A and B, and a third person C for the link. Watch the sync status under Account on each.

1. A invites B with Invite with iCloud. B accepts once with the app closed and once with it open. The group opens on B, and B is on A's member list once.
2. A and B edit the same expense while offline, then go online. Both end up with the same version.
3. B taps Leave Group. B is gone from A's member list and from A's invite sheet, and B shows no sync error. A invites B again and the history comes back.
4. A makes a link and C joins with it. A sets the invite sheet to invited people only: the group leaves C's phone. A opens the link again and C joins again.
5. A invites B by name and then opens the link. B still has the group.
6. A stops sharing: the group leaves B's phone and stays on A's. A shares again, then deletes the group: it leaves B's phone.
7. On A, open Settings, iCloud, Manage Account Storage, Splt, and delete its data. A's groups stay on A's phone and are not uploaded again.
8. Tap an invite link with the app closed and the phone in airplane mode, then go online within a minute. The group opens.

## Known limits

- Sharing and push only work on real devices signed in to iCloud. The simulator cannot be used to test them.
- Everyone needs an Apple ID and iCloud turned on. People without it can still be placeholders.
- Claiming a placeholder is refused while the placeholder and the real person both paid, or both have a share, in one expense, or one paid the other, because their amounts would need merging by hand. Deleted expenses do not count.
- Two people editing the same record before either has synced can lose a change, even in different fields: the later edit replaces the whole record. This also applies to a group's member list and a comment's reactions. Separate records, such as two new expenses, never conflict.
- Receipt photos stay on the device that scanned them. Only the file name syncs.
- After switching iCloud accounts, groups already on the device stay as local copies and are not uploaded to the new account.
- After you delete Splt's data in the iCloud storage settings, your groups stay on each device as local copies and are not uploaded again. Groups you make afterwards sync as usual.
- Closing a link does not take the people it removed off the group's member list. Remove them in the group's settings, or invite them again by name.
- A device that stays offline for a very long time may have to refetch everything. A comment or person deleted elsewhere in the meantime can come back until it is deleted again.
- Deleting a shared group as its owner removes it for everyone.
- A group is stored in its owner's iCloud. When the owner's storage is full, nobody can upload changes to that group, and the app tells the others it is the owner's storage. Changes stay on each device and sync once space is available.
