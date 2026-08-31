---
tags: [chataa, supabase, database, backend, security]
status: active
updated: 2026-08-29
---

# Chataa Supabase and Database

Hub: [[Chataa]]

## Current Supabase Project

| Item | Value |
|---|---|
| Project ref | `ycbuwrhnhdsbutbfzsvn` |
| URL | `https://ycbuwrhnhdsbutbfzsvn.supabase.co` |
| Client config file | `HoroTest/SupabaseConfig.plist` |

Do not write the secret key into the iOS project, Git, or Obsidian notes.

## Current App Connection Points

| App function | Supabase source |
|---|---|
| Login/auth test accounts | Supabase Auth plus `account` |
| Wallet balance | `v_my_wallet` |
| Seer list | `seer_profile`, `seer_service`, `seer_skill`, `skill` |
| Start paid chat/question | RPC `submit_question` |
| Chat messages | `question_message` |
| Question rows | `question` |

## Important Tables and Views

| Area | Tables/views |
|---|---|
| Identity | `account`, `user_profile` |
| Seer profile | `seer_profile` |
| Skills | `skill`, `seer_skill` |
| Services | `seer_service` |
| Paid reading/chat | `question`, `question_message` |
| Wallet and ledger | `wallet`, `ledger_transaction`, `ledger_entry` |
| Payment | `coin_package`, `payment_order`, `iap_receipt` |
| Safe wallet reads | `v_my_wallet`, `v_my_coin_history`, `v_my_payment_history` |
| Safety | `block_relation`, rate-limit tables/functions |
| Onboarding | `seer_application`, `seer_document` |

## Money Rules

- Client reads wallet through views.
- Client must not write `wallet`, `ledger_transaction`, or `ledger_entry` directly.
- Customer spending must use server-side RPCs.
- Payment crediting must use verified server/Edge Function paths.
- Prices must come from `seer_service`, not from client UI strings.

## Current Mock Gaps

| UI feature | Needed backend work |
|---|---|
| Booking page | Real booking/availability tables and RPCs. |
| 15/30/60 minute calls | Call session tables, provider choice, charge/settle RPCs. |
| Seer revenue dashboard | View over ledger/payments, for example `v_my_seer_earnings`. |
| QR payment | `create_payment_order` RPC plus PromptPay/PSP Edge Function. |
| Profile edit | Update `user_profile` / `seer_profile` and image storage upload. |
| Reviews | Review table, tags, rating aggregation, submit review RPC. |

## Recommended New Views/RPCs

| Name | Purpose |
|---|---|
| `v_seer_discovery` | Card-ready rows for customer find-seer page. |
| `v_question_inbox` | Chat inbox rows with last message and unread state. |
| `mark_question_read(question_id, last_message_id)` | Read cursor update for unread badges. |
| `v_my_seer_earnings` | Revenue rows for `ยอดดูดวง` daily/monthly/yearly filter. |
| `create_booking(...)` | Reserve a seer period safely. |
| `v_seer_availability` | Date/period availability for booking page. |
| `create_payment_order(...)` | Real QR/card/bank transfer top-up order. |
| `submit_review(...)` | Customer review after completed reading. |

## Test Accounts

| Login | Email | Role |
|---|---|---|
| `customer` | `customer@horo.test` | Customer |
| `seer` | `seer@horo.test` | Seer |

Default test password is `HoroTest123!` unless `SUPABASE_TEST_PASSWORD` overrides it.

## Security Reminder

The Supabase secret key was shared during development. Treat it as exposed and rotate it before production work.
