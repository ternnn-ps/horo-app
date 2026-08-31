---
tags: [chataa, devlog, ios, swiftui]
status: active
date: 2026-08-29
---

# Chataa Development Log 2026-08-29

Hub: [[Chataa]]

## Product Naming

Decision from user: the app will be named **Chataa**.

Current code still contains Horo/HoroTest names. Rename should be a separate careful change.

## UI/UX Work Completed Recently

### Roles

- Replaced `teller` wording with `seer`.
- Login supports `seer` and `customer`.
- Role selection is not displayed in profile menus.

### Navigation

- Seer tabs: Chat, Dashboard, Profile.
- Customer tabs: Home, Chat, Profile.
- Bottom tab labels follow the selected app language.

### Language

- Added app-wide English/Thai setting in profile.
- Main navigation and many function labels switch language.

### Appearance

- Added app-wide System/Light/Dark setting.
- UI colors use dynamic SwiftUI/system colors.

### Customer Home

- Improved customer home page.
- Added find-seer menu.
- Added searchable seer list.
- Seers show in 2-column cards.
- Seer cards show image, skills, styles, rating, rate, and availability.

### Seer Detail and Booking

- Seer detail shows large image/card, skills, styles, bio, message, book, and call actions.
- Booking opens a page/sheet with date selection.
- Booking has morning/afternoon/evening period selection.
- Already-booked periods are displayed and disabled.
- Booking confirmation uses coins in the mock balance.
- Call options include 15 minutes, 30 minutes, and 1 hour.

### Wallet and Payment Mock

- Wallet uses THB top-up wording.
- Coin icon uses `C`.
- QR payment method added as a mock option.
- Current real QR payment flow is not connected.

### Seer Dashboard

- Added reading revenue section named `Reading Revenue` / `ยอดดูดวง`.
- Revenue filter supports daily, monthly, yearly.
- Revenue rows show customer, service type, timestamp, and THB received.
- Current revenue rows are mock data.

### Seer Profile

- Seer profile now shows a large display-picture card.
- Camera/change icon only appears in edit profile mode.
- Seer profile shows rating and review count.
- Seer profile shows personality traits.
- Seer profile shows skill types.
- Edit profile uses chips for selecting which traits and skills appear publicly.

## Latest Verification

Simulator was not run.

Used safe checks:

```sh
xcrun --sdk iphoneos swiftc -parse-as-library -typecheck -target arm64-apple-ios26.1 $(rg --files HoroTest -g '*.swift')
xcodebuild -project HoroTest.xcodeproj -scheme HoroTest -destination 'generic/platform=iOS' build
```

Both passed after the latest SwiftUI changes.

## Next Recommended Development Tasks

1. Rename app/project branding to Chataa in a controlled pass.
2. Connect seer revenue dashboard to a real Supabase view.
3. Connect booking periods to real availability/reservation data.
4. Sync profile edit fields to Supabase.
5. Add real review and rating flow.
6. Add real QR/PromptPay payment flow.
7. Add block/report before public chat testing.
