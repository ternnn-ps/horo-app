---
tags: [chataa, roadmap, ux, product]
status: active
updated: 2026-08-29
---

# Chataa UX Roadmap

Hub: [[Chataa]]

## Near-Term UX Improvements

1. Rename visible app branding from Horo/HoroTest to Chataa.
2. Make customer seer discovery use real `v_seer_discovery` rows.
3. Make booking availability come from Supabase instead of mock periods.
4. Add unread badges to chat tabs and inbox rows.
5. Add block/report actions in chat and seer profile overflow menus.
6. Add review submission after a completed reading.
7. Add profile image upload using Supabase Storage.
8. Add empty/error/loading states to every Supabase-backed screen.

## Customer Flow Roadmap

| Priority | Feature |
|---|---|
| High | Real wallet balance everywhere from `v_my_wallet`. |
| High | Real seer discovery and seer detail. |
| High | Real chat inbox from `question` / `question_message`. |
| High | Real booking and unavailable periods. |
| Medium | PromptPay/QR top-up order creation. |
| Medium | Reading history and receipt screen. |
| Medium | Review/rating flow after completed reading. |
| Later | Horoscope/AI content, vouchers, referral, live/gifts. |

## Seer Flow Roadmap

| Priority | Feature |
|---|---|
| High | Real queue from `question`. |
| High | Real reading revenue from ledger/payable rows. |
| High | Seer profile edit sync to `seer_profile`. |
| High | Availability editor for booking periods. |
| Medium | Payout request/status UI. |
| Medium | Review management and public profile preview. |
| Later | Voice/video call provider integration. |

## Recommended Screens To Design In Google Stitch

Use Stitch for visual direction, then convert to SwiftUI:

- Customer Home
- Find Seer
- Seer Profile Detail
- Booking Date/Period
- Chat Inbox
- Chat Detail
- Seer Dashboard
- Seer Revenue
- Seer Profile Editor
- Payment Top-Up

## Product Tone

Chataa should feel trustworthy, calm, and warm. It should avoid feeling like a casino or a flashy fortune-telling gimmick. The money and booking flows should be very clear because users need to understand when coins are held, spent, refunded, or paid to a seer.
