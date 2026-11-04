# App Store Connect

Copy for the first release. Limits are Apple's. Keep this file in step with the app.

## Name

Splt

## Subtitle

Split bills with friends

## Promotional text

Free forever. No ads, no accounts, no limits. Split trips, rent and dinners, and keep your data in your own iCloud.

## Description

Splt splits costs with friends, roommates and travel groups. It is free, and it stays free: no ads, no accounts, no limits on groups or expenses, and no subscription, now or later.

Add an expense and say who paid and who shares it. Splt keeps a running balance and shows the fewest payments that settle everyone up.

Splitting
- Equally, by exact amounts, percentages, shares, adjustments, or item by item
- Any currency per expense, with reference exchange rates or a rate you set for the trip
- Recurring expenses for rent and subscriptions you share

Faster entry
- Type a sentence like "dinner 60 with Sam and Priya" and check the result
- Dictate an expense by voice
- Scan a receipt with the camera and split it by item
- Categories are suggested for you

Settling up
- Record a payment and note how it was made
- Open your payment app with the amount filled in
- Send a gentle reminder to a friend who owes you

Together
- Invite people to a group through iCloud
- Comments on expenses, with translation
- An activity feed shows what changed

Private by design
- No account. Your Apple Account is your identity
- Your data stays on your device and in your own iCloud
- No analytics, no tracking, no ads
- Smart features run on the device

Also
- Search in plain language, in Spotlight, and with Siri and Shortcuts
- Totals, charts and a trip recap for each group
- Export a group as a spreadsheet or PDF
- Open source, so anyone can read how it works

Splt does not move money. It keeps the books, and you pay each other the way you already do.

## Keywords

split,bills,expenses,roommates,trip,group,shared,settle,receipt,debts,iou,friends,costs,rent,travel

## Category

Primary: Finance. Secondary: Lifestyle.

## URLs

| Field | Value |
| --- | --- |
| Support URL | https://harrypakhale98.github.io/Splt/support |
| Marketing URL | https://harrypakhale98.github.io/Splt/ |
| Privacy Policy URL | https://harrypakhale98.github.io/Splt/privacy |

Turn on GitHub Pages first: repository Settings, Pages, deploy from branch `main`, folder `/docs`.

## Age rating

Answer None or No to every question. The expected rating is 4+.

| Question | Answer |
| --- | --- |
| Violence, sexual content, nudity, profanity, horror, drugs, alcohol, tobacco | None |
| Gambling, contests, simulated gambling | None |
| Medical or wellness content | None |
| Unrestricted web access | No |
| Content posted by users, messaging and chat | No, see the note below |
| Advertising | No |
| Parental controls, age assurance | No |

Note: members of a private group can comment on expenses. There is no public content, no discovery of strangers and no open chat. If App Store Connect words the question so that this counts, answer Yes for private, invite only groups. The rating should still be 4+.

## App Privacy

| Question | Answer |
| --- | --- |
| Do you or your third party partners collect data from this app | No |
| Data types | Data Not Collected |
| Tracking | No |

This matches `PrivacyInfo.xcprivacy` and [privacy.md](privacy.md). Splt has no server, and iCloud data belongs to the user's Apple Account. The exchange rate lookup sends no identifiers and no user data, and the service is only asked for a public table, so it is not collection. Revisit this answer if the lookup ever sends anything more.

## Export compliance

Splt uses no encryption of its own. It relies on the encryption in iOS (iCloud and system networking). Answer that it qualifies for the exemption. The hashing used for identifiers is not encryption.

## Review notes

Splt has no sign in, so there is no demo account.

To try it:
1. Open the app and tap New Group on the Groups tab. Give it a name and add two people by typing their names.
2. Open the group and tap Add Expense. Enter "Dinner" and an amount, choose who paid and keep the equal split.
3. Open the group's balances and tap Settle Up to record a payment.

Everything above works offline and without an Apple Account.

Optional features:
- iCloud sync and group invites need a signed in iCloud account and a second device. Without iCloud the app runs on local data only.
- Receipt scanning asks for camera access. Voice entry asks for microphone access.
- Quick add and category suggestions use Apple's on-device language model on devices that have it. On other devices they use simple rules.
- Splt asks the free Frankfurter service for exchange rates when an expense is in another currency. The request holds only a currency code and a date. It is skipped when a rate is pinned or the device is offline.
- Settle Up can open payment apps. Splt never handles payments.

Contact: name, phone and email go in App Store Connect.

## Screenshots

iPhone only. Upload the 6.9 inch set (1320 by 2868). Smaller sizes scale from it.

Use a Debug build launched with the `-sampledata` argument, so every screenshot shows the same trip. Use light mode, plain captions, no device frames.

| # | Screen | Caption |
| --- | --- | --- |
| 1 | Groups list with balances | Everyone's balance at a glance |
| 2 | Group detail with expenses | Every expense in one place |
| 3 | Add Expense with quick add | Type it the way you say it |
| 4 | Split options | Split any way you like |
| 5 | Receipt scan, split by item | Scan a receipt, split by item |
| 6 | Settle Up | Settle up in a tap |
| 7 | Group totals and trip recap | See where the money went |

Add a dark mode shot of screen 2 if there is room.

## Release checklist

Accounts and signing
- [ ] Enroll in the Apple Developer Program. The fee is the only cost of shipping.
- [ ] Register the App ID `com.harrypakhale.splt` with iCloud (CloudKit) and Push Notifications.
- [ ] Create the container `iCloud.com.harrypakhale.splt` in the developer portal, or let Xcode create it with automatic signing.
- [ ] Check that `Splt/Sync/Splt.entitlements` names the same container. The distribution profile switches the push environment to production.

CloudKit
- [ ] Run a Debug build on a device and use every feature once, as [sync.md](sync.md) describes.
- [ ] In the CloudKit Dashboard, deploy the schema to Production.

Version
- [ ] Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- [ ] Run the tests and the CI workflow on the release commit.

TestFlight
- [ ] Archive, validate and upload from Xcode.
- [ ] Install on two real devices with different Apple Accounts. Create a group, invite, accept, edit on both sides and edit while offline.
- [ ] Check that notifications and the privacy report in the archive show no tracking.

Submit
- [ ] Paste the copy above, add screenshots, answer the age rating, App Privacy and export questions.
- [ ] Paste the review notes and add contact details.
- [ ] Tag the release in git, for example `v1.0.0`.
