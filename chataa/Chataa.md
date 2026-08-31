---
tags: [project, chataa, ios, swiftui, supabase, astrology]
status: active
created: 2026-08-29
updated: 2026-08-29
aliases: [Chata, Horo, HoroTest]
---

# Chataa

Chataa is the current product name for the iOS astrology and seer consultation app.

This vault keeps the product decisions, current app state, database notes, development setup, and roadmap together.

## Current Naming

| Area | Current value | Note |
|---|---|---|
| Product name | Chataa | Use this name in new planning notes. |
| Obsidian folder | `chataa/` | Current vault folder. |
| iOS project | `HoroTest.xcodeproj` | Still needs rename later. |
| iOS display name | `Horo Test` | Still needs rename later. |
| Bundle id | `com.pacharapol.HoroTest` | Change carefully before IAP/TestFlight. |
| DB/deep link legacy name | `chata` / `chata://` | Keep until backend rename plan is agreed. |

## Main Notes

- [[Chataa Current App State]]
- [[Chataa Architecture]]
- [[Chataa Supabase and Database]]
- [[Chataa Build and Device Notes]]
- [[Chataa UX Roadmap]]
- [[Chataa Development Log 2026-08-29]]

## Historical Notes

Older notes use the working name Chata and Horo. Keep them as project history:

- [[Chata]]
- [[Chata Architecture]]
- [[Chata iOS Phase 3]]
- [[Chata Phase 4 Payout and Call]]
- [[Chata Progress 2026-08-29]]

## Product Summary

Chataa has two primary roles:

| Role | Purpose |
|---|---|
| Customer | Finds seers, adds coins, books readings, sends questions/messages, and manages profile/settings. |
| Seer | Handles chat queue, views dashboard, tracks reading revenue, manages profile, traits, skills, and local reading notes. |

The current app is a SwiftUI prototype with partial Supabase integration. It can run on iOS 26.1 physical devices. Do not run the iOS Simulator on this Mac because it has caused freezing during development.

## High-Level Status

| Area | Status |
|---|---|
| SwiftUI app shell | Working |
| Customer workspace | Mock plus partial Supabase |
| Seer workspace | Mock plus local CRUD |
| Thai/English language setting | Working in main UI |
| Light/Dark mode setting | Working |
| Supabase login test accounts | Prepared |
| Wallet read from `v_my_wallet` | Prepared in app service |
| Seer list from Supabase | Prepared in app service |
| Chat question/message API | Prepared in app service |
| Booking page | Mock only |
| Call packages | Mock only |
| Seer revenue dashboard | Mock only |
| Profile edit | Local UserDefaults only |
| Real payment / QR payment | Mock only |

## Immediate Decision

Before production payment or TestFlight work, decide whether to rename the iOS target, bundle id, app icon labels, Supabase deep links, and product ids to Chataa in one coordinated change.
