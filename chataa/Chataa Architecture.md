---
tags: [chataa, architecture, ios, supabase]
status: active
updated: 2026-08-29
---

# Chataa Architecture

Hub: [[Chataa]]

## Repo Shape

```text
horo-app/
├── HoroTest/                 iOS SwiftUI app
├── HoroTest.xcodeproj        Xcode project
├── HoroTestTests/            XCTest target
├── chataa/                   Obsidian vault
├── docs/specs/               DB and product specs
├── db/                       DBML and database tests
├── supabase/                 Migrations and Edge Functions
└── scripts/                  Test and fixture scripts
```

## iOS Layers

```text
SwiftUI View
  -> ViewModel / local state
  -> SupabaseHoroDataService
  -> Supabase REST/RPC/Auth endpoints
```

Current local state still exists for some prototype-only features:

- `UserDefaultsRecordStore` for local seer reading notes.
- `UserDefaultsUserProfileStore` for local profile edits.
- In-memory chat fallback for mock conversations.

## Backend Boundary

Supabase acts as the backend:

| Backend concern | Chataa mechanism |
|---|---|
| Auth | Supabase Auth |
| Safe reads | RLS-protected tables and views |
| Money writes | RPC / Edge Functions only |
| Chat messages | `question_message` |
| Paid reading room | `question` |
| Wallet | `wallet` behind `v_my_wallet` |
| Payment verification | Edge Function path |

## Security Rule

The iOS app must never store or use `SUPABASE_SECRET_KEY`.

Allowed in app:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- test password for local/dev test accounts

Backend-only:

- `SUPABASE_SECRET_KEY`
- payment provider secrets
- Apple/Google receipt verification secrets
- JWKS/token verification logic when acting as a backend verifier

## Mobile Constraint

Backend changes must be backward compatible. Users can keep old app versions on their phones, so database and API contracts should evolve using expand-then-contract:

1. Add new fields/views/RPCs.
2. Update app.
3. Wait for adoption.
4. Remove old contracts only when safe.

## Design Workflow

Google Stitch can be used as a design ideation tool:

1. Generate Chataa screens in Stitch.
2. Export/screenshot/Figma the design.
3. Convert the visual direction into SwiftUI manually.

Stitch output is web-oriented, so it is not drop-in SwiftUI code.
