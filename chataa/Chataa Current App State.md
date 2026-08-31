---
tags: [chataa, ios, current-state, ux, swiftui]
status: active
updated: 2026-08-29
---

# Chataa Current App State

Hub: [[Chataa]]

## App Platform

- Native iOS app built with SwiftUI.
- Current Xcode project name: `HoroTest.xcodeproj`.
- Current deployment target: iOS 26.1.
- Current display name in Xcode project: `Horo Test`.
- Product name decision: use **Chataa** going forward.

## Login

The app has a simple test login flow:

| Login text | Role |
|---|---|
| `customer` | Customer workspace |
| `seer` | Seer workspace |

Password can be empty for test mode. The app falls back to `SUPABASE_TEST_PASSWORD` or `HoroTest123!`.

## Shared App Features

- App-wide language setting: English / Thai.
- App-wide appearance setting: System / Light / Dark.
- Profile menu contains language, appearance, and logout.
- Role selection is not shown inside profile menus.
- Bottom tab navigation is role-specific.
- The UI uses adaptive SwiftUI colors for dark mode and light mode.

## Customer Workspace

Main tabs:

| Tab | Purpose |
|---|---|
| Home | Overview, active reading, quick actions, find seer. |
| Chat | Inbox and mock/API-backed chat detail. |
| Profile | Customer profile, wallet, language, appearance, logout. |

Customer features:

- Home page with customer summary and current coin balance.
- Find seer view with search.
- Seer cards shown in a 2-column grid.
- Seer cards show picture, rating, detail, price, skills, and availability.
- Seer profile page has message, book, call package, skills, styles, and bio sections.
- Booking page has date selection, period selection, and already-booked periods.
- Booked periods are visible and disabled.
- Call options support 15 minutes, 30 minutes, and 1 hour.
- Wallet mock shows THB top-up to in-app coins.
- QR payment appears as a mock payment method.
- Customer profile edit supports local profile picture style changes.

## Seer Workspace

Main tabs:

| Tab | Purpose |
|---|---|
| Chat | Customer queue/inbox and chat detail. |
| Dashboard | Operations metrics, revenue history, queue preview, reading notes. |
| Profile | Seer profile, reputation, traits, skills, settings, logout. |

Seer features:

- Dashboard has queue, active, and done metrics.
- Dashboard has reading revenue section named `Reading Revenue` / `ยอดดูดวง`.
- Revenue can be filtered by daily, monthly, and yearly.
- Revenue rows show customer name, service type, time, and THB amount received.
- Seer profile shows a large display picture card.
- Profile shows rating and review count.
- Profile shows personality traits such as Listener, Talkative, Fun/Funny, Calm, Comforting.
- Profile shows skill types such as Tarot, Oracle, Sacred, and 7 ตัว 9 ฐาน.
- Edit profile changes display picture style.
- Edit profile uses selectable chips for traits and skills.
- Local reading notes support create, read, update, delete, and mark done/active.

## Current Mock Areas

These flows are UI-ready but not yet fully connected to backend truth:

- Booking availability and already-booked periods.
- 15/30/60 minute calls.
- Seer reading revenue history.
- Profile edit sync.
- Review submission.
- Real QR payment / PromptPay payment.
- Push notifications.

## Current Supabase-Backed Areas

The app has service code prepared for:

- Auth/login for test accounts.
- Wallet from `v_my_wallet`.
- Seer list from `seer_profile`, `seer_service`, `seer_skill`, and `skill`.
- Chat/question creation through `submit_question`.
- Messages through `question_message` insert/read.

See [[Chataa Supabase and Database]].
