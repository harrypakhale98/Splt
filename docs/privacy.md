# Privacy

Last updated: November 2026

Splt does not collect your data. There is no Splt server, no account and no analytics. The one outside service it talks to is a free exchange rate lookup, described below.

## Where your data lives

- On your iPhone, in the app's own storage, and in that iPhone's backup if you back it up.
- In your own iCloud, if you are signed in to iCloud. Splt uses Apple's CloudKit to keep your devices in step and to share a group with the people you invite. This data belongs to your Apple Account and counts against your iCloud storage. We cannot see it.

If you turn iCloud off, Splt keeps working and keeps everything on the device.

## Who can see a group

You and the people who join that group. There are two ways to invite. Invite with iCloud sends an invitation to the people you choose, and only they can join. Link or QR Code makes a link that anyone who has it can use to join, so send it only to people you trust. You can close the link again in Invite with iCloud, under who can join, which also removes the people who joined through it. People who join can see the group's members, expenses, payments and comments. Everyone in a group can add, change and remove what is in it.

An email address or phone number that you pick from Contacts stays on your device. It is not shared with the group.

## What Splt does not do

- It does not track you or use an advertising identifier.
- It does not include ads, analytics or crash reporting from other companies.
- It does not send your groups, people, amounts or notes anywhere except your own iCloud.
- It does not read your contacts. When you add someone from Contacts, the system picker hands Splt only the people you choose.

## Exchange rates

When an expense is in another currency than its group, Splt can look up a rate from Frankfurter (api.frankfurter.dev), a free service that publishes European Central Bank reference rates. The request holds a currency code and sometimes a date. It holds no account, no identifier and nothing about your groups. Like any web request, it shows your IP address to that service. Rates are cached on the device. If you pin a rate for a group, Splt uses it and does not ask.

## Features that use the device

- **Camera.** Receipts are scanned on the device with Apple's frameworks. A receipt photo you keep stays on the device that scanned it and that device's backup. Only its file name syncs.
- **Photos and files.** When you attach a receipt from your photo library or import a Splitwise file, the system picker hands Splt only the photo or file you choose.
- **Microphone and speech.** Voice entry is turned into text on the device.
- **Smart entry and suggestions.** These use Apple's on-device language model when it is available.
- **Translation.** Comments are translated with Apple's system translation.
- **Notifications.** Reminders are local notifications that Splt schedules on your device. A notice about a friend's change is built on your device after iCloud wakes the app. Splt has no push server.
- **Spotlight and Siri.** Group and friend names, and who is in each group, go into the search index on your device so Spotlight and Siri can find them. Adding an expense or hearing a balance through Siri needs an unlocked iPhone.
- **Pay with.** When you tap a payment app in Settle Up, Splt opens that app or its website with the amount and a short note. Splt never handles the payment, and what the other app does with it is up to that app.

## Exports

Exporting a group as CSV, PDF or JSON creates a file on your device. It goes where you send it from the share sheet, and nowhere else.

## Backups

Back Up Everything, in Account, makes one file with your groups, people, expenses, payments, comments and activity, and your receipt and group photos unless you turn Include Photos off. It also holds the email addresses and phone numbers you picked for people. It holds no iCloud account details. The file is made on your device and goes only where you save or send it from the share sheet. Splt never uploads it anywhere, so keep it somewhere safe and treat it like any file with your finances in it. Restoring a backup reads the file on your device and adds what it holds to your own groups.

## Balance links

Share as a Link, in a group's share menu, makes a web link for a friend without an iPhone. The group's name, trip dates, people's names and colours, who pays whom and, if you leave Recent expenses on, the latest ten expenses with each person's share are packed into the link itself, after the "#". Browsers never send that part to a server, so the page on this website reads it in the browser and nothing is uploaded. The page loads nothing from any other site and runs no analytics. The link holds no contact details, no account and no identifiers. It is a snapshot that never changes, and it can't be taken back: anyone who has it can see those names and amounts, so send it only to the people in the group. The page remembers which person you chose, in your browser only.

## Deleting your data

Deleting a group in the app removes it from your devices and your iCloud. Its receipt photos are removed from a device the next time Splt opens there. If you own a shared group, it is removed for everyone in it. To clear everything Splt has stored in iCloud, open Settings, then your name, then iCloud, then Manage Account Storage, choose Splt and delete its data. Your groups then stay on your devices as local copies. Versions after 1.0.0 do not upload them again. Deleting the app removes what it stored on the device.

## Children

Splt has no accounts and collects nothing, so there is nothing about children to collect.

## Changes

If this ever changes, the change will be in this file with a new date, and in the project history on GitHub.

## Contact

Open an issue at [github.com/harrypakhale98/Splt/issues](https://github.com/harrypakhale98/Splt/issues). For a private matter, see [SECURITY.md](https://github.com/harrypakhale98/Splt/blob/main/SECURITY.md).
