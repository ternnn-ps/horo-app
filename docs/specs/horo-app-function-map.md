# Horo App Function Map From Current DB Design

Status: draft for iOS app implementation

This document maps the current Supabase database design to the Horo iOS app functions. The DB docs and migrations still use the older project name `Chata`; the mobile app can keep the Horo brand while using the existing table/RPC names.

## 1. DB Coverage Found

Implemented migrations already cover these production-shaped areas:

| Area | Main DB objects | App meaning |
|---|---|---|
| Identity | `account`, `user_profile`, `seer_profile` | Login role, profile display, customer/seer status |
| Seer catalog | `skill`, `seer_skill`, `seer_service` | Find seer cards, skills, active services, coin prices |
| Consultation chat | `question`, `question_message` | Paid question/chat session between customer and seer |
| Money | `wallet`, `ledger_transaction`, `ledger_entry` | Coin balance, reserved coins, seer payable coins |
| Payment | `coin_package`, `payment_order`, `iap_receipt` | THB-to-coin packages and verified purchases |
| Read views | `v_my_wallet`, `v_my_coin_history`, `v_my_payment_history` | Safe client reads for money tables |
| Operations | `notification_inbox`, `outbox_event`, `audit_log`, `app_config` | Push, background jobs, audit, feature flags |
| Safety | `block_relation`, rate-limit functions | Block/unblock, anti-spam for messages and questions |
| Seer onboarding | `seer_application`, `seer_document`, related RPCs | Apply to become a seer, upload documents, admin review |

The full design documents include future areas that are not fully present in phase-1 app migrations yet: appointment rooms, call transactions, call extensions, payouts, review tags, horoscope/AI, live rooms, and gifts.

## 2. Important DB Rules For The App

Money tables are intentionally private. The app should never write `wallet`, `ledger_transaction`, `ledger_entry`, `payment_order`, or `iap_receipt` directly.

Customer coin balance should be read from `v_my_wallet`.

Coin history should be read from `v_my_coin_history`.

Payment history should be read from `v_my_payment_history`.

Coin packages can be read from `coin_package` where `is_enabled = true`.

Paid question creation must call `submit_question(...)`. That RPC reserves customer coins in escrow and creates the first `question_message`.

Question lifecycle actions must call RPCs: `cancel_question`, `request_close_question`, `cancel_close_request`, and `respond_close_question`.

IAP crediting is server-only. The app should call the Edge Function `verify-iap`; the function verifies the store receipt and then calls `internal_credit_iap`.

## 3. App Function Design

| App screen/function | DB read | DB write/RPC | Notes |
|---|---|---|---|
| Login | Supabase Auth, `account` | Supabase Auth | Current mock role login should become real auth session bootstrap. |
| App bootstrap | `account`, `user_profile` or `seer_profile`, `v_my_wallet`, public `app_config` | None | Decide customer/seer UI from `account.role`. |
| Customer home | `user_profile`, `v_my_wallet`, active `question` rows | None | Replace local coin state with wallet view. |
| Find Seer | `seer_profile`, `seer_skill`, `skill`, `seer_service` | None | Query approved, active seers with enabled services. |
| Seer detail | `seer_profile`, `seer_skill`, `skill`, `seer_service` | None | Show profile, skills, styles, rating, coin price. |
| Add coins | `coin_package`, `v_my_wallet` | `verify-iap` Edge Function | DB currently implements IAP path. QR/PromptPay needs a new non-IAP order flow. |
| Customer sends first paid question | `seer_service`, `v_my_wallet` | `submit_question` | Pass `seer_service_id`, first message, `client_message_id`, and `client_request_id`. |
| Customer chat inbox | `question`, latest `question_message` | None | Current Swift mock `ChatThread` should be replaced by question-based inbox rows. |
| Chat detail | `question_message` ordered by `id` | insert `question_message` | Direct insert is allowed by RLS for participants, with rate-limit trigger. |
| Close/cancel reading | `question.status` | lifecycle RPCs | UI should reflect `submitted`, `active`, `close_requested`, `completed`, `cancelled_refunded`. |
| Seer dashboard | `question`, `question_message`, `v_my_wallet` | lifecycle RPCs | Seer sees queue, unread messages, active work, payable coins. |
| Profile edit | `user_profile` or `seer_profile`, `profile_photo` later | update profile rows, storage upload later | Current avatar style is local mock; real DB uses `avatar_url` and `profile_photo`. |
| Settings | `user_profile` notification columns, public `app_config` | update `user_profile` | Dark/light mode can remain local `AppStorage`; notification prefs can go to DB. |
| Block user/seer | `block_relation` | `block_account`, `unblock_account` | Use in chat/profile overflow menu. DB resolves open question escrow during block. |
| Seer onboarding | `seer_application`, `seer_document` | `save_seer_application`, `submit_seer_application` | Add customer path to apply as seer after core chat/wallet works. |

## 4. Mismatches To Fix Before Real Supabase Wiring

The Swift models currently use older scaffold names like `HoroUser`, `ReadingRequest`, `ChatThread`, and `ChatMessageRecord`. The real DB uses `account`, `user_profile`, `seer_profile`, `question`, and `question_message`. The app data layer should be refactored to match the actual migration names before implementing Supabase queries.

The mock wallet now shows "Add THB to Coins" with QR payment, but the implemented backend top-up path is IAP-only right now. The schema can represent `promptpay`, `card`, and `bank_transfer`, but there is no client-callable `create_payment_order` RPC or PromptPay/QR Edge Function in the current migrations.

The mock call booking offers 15 min, 30 min, and 1 hr sessions. The full DB design has call tables, but the current implemented migrations only support `chat_question`. Keep call booking as mock until `service_type`, `call_transaction`, `call_extension`, and media session migrations are added.

The mock app icon/coin icon are UI-only assets. DB coin accounting is ledger-based and should not depend on those visuals.

## 5. Recommended Backend Additions For This App UI

| Priority | Addition | Why |
|---|---|---|
| 1 | `v_seer_discovery` view | Return card-ready seer rows with skills, main service price, avatar, rating, active flags. |
| 2 | `v_question_inbox` view | Return chat inbox rows for customer and seer with last message, unread count, status, and counterpart profile. |
| 3 | `mark_question_read(question_id, last_message_id)` RPC | Update read cursors safely for unread badges. |
| 4 | `create_payment_order(coin_package_id, method, idempotency_key)` RPC | Needed for QR/PromptPay/card/bank transfer top-up flow. |
| 5 | PromptPay/QR Edge Function | Generate QR payload, reconcile PSP result, then call `internal_credit_payment`. |
| 6 | Call-session migrations/RPCs | Needed before real 15/30/60 min call booking can spend coins safely. |

## 6. Recommended iOS Implementation Order

1. Keep the current mock UI, but introduce real DTOs that match the Supabase tables.
2. Replace customer wallet mock state with `v_my_wallet`.
3. Replace top-up packages with `coin_package`.
4. Implement IAP top-up through `verify-iap` first.
5. Replace Find Seer mock data with a DB-backed discovery query or `v_seer_discovery`.
6. Replace mock chat with `question` and `question_message`.
7. Connect seer dashboard to `question` queues.
8. Add block/unblock actions in chat and seer profile menus.
9. Add seer onboarding screens after core customer flow works.
10. Add QR/PromptPay only after the backend has the order RPC and PSP Edge Function.

## 7. Short Conclusion

The database design is strong for a paid chat-question marketplace: role identity, seer catalog, escrow, append-only ledger, idempotent payment crediting, RLS, rate limiting, lifecycle jobs, block safety, and onboarding are already designed or migrated.

The best next app step is not to create more mock screens. The next useful step is to refactor the iOS data models to the real DB naming and connect customer wallet, coin packages, seer discovery, and paid question chat to Supabase one by one.
