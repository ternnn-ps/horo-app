# HoroTest

A simple SwiftUI iOS test app for a mock seer and customer workflow. It includes role login, a customer chat queue, seer dashboard, customer home space, profile screens, local CRUD records, and an XCTest unit test target.

Minimum iOS version: **iOS 26.1**.

## What You Need

- Xcode installed from the App Store or Apple Developer downloads.
- iOS 26.1 or newer platform support installed in Xcode.
- An Apple ID added in Xcode Settings > Accounts.
- Developer Mode enabled on your iPhone.
- Xcode selected as the active developer directory:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

- Optional: an iOS Simulator installed from Xcode Settings > Platforms if you also want simulator runs.

## Run On iPhone

1. Open `HoroTest.xcodeproj` in Xcode.
2. Connect your iPhone with USB or make sure wireless debugging is enabled.
3. Select your iPhone from the device picker.
4. Open the HoroTest target > Signing & Capabilities.
5. Select your Apple Development Team and keep Automatically manage signing enabled.
6. Press Cmd+R to run the app.

The app bundle identifier is `com.pacharapol.HoroTest`.

If Xcode says the bundle identifier is already used, change it to something unique like `com.yourname.HoroTest`.

## Supabase Connection

The app can read Supabase settings from Xcode build settings, generated Info.plist values, or Xcode scheme environment variables:

```sh
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
SUPABASE_TEST_PASSWORD=HoroTest123!
```

The older aliases `HORO_SUPABASE_URL`, `HORO_SUPABASE_ANON_KEY`, and `HORO_TEST_PASSWORD` still work too.

Do not put `SUPABASE_SECRET_KEY` in the iOS app. Keep it only in Supabase Edge Functions or another trusted backend. `SUPABASE_JWKS_URL` is also backend-facing for token verification and is not needed by the current iOS client.

For the current test login, create Supabase Auth users for `customer@horo.test` and `seer@horo.test` with the same test password. Typing `customer` or `seer` in the app logs into those emails; if the password box is empty, the app uses `SUPABASE_TEST_PASSWORD` or `HoroTest123!`.

## Current Features

- Light Mode and Dark Mode-friendly SwiftUI colors.
- App-wide appearance setting in profile menus for System, Light, and Dark mode.
- App-wide language setting in profile menus for English and Thai.
- Mock login page. Type `seer` or `customer`; the password field can be empty.
- Passwordless test accounts for customer and seer chat testing.
- Seer bottom tab navigation for Chat, Dashboard, and Profile.
- Customer bottom tab navigation for Home, Chat, and Profile.
- Mock seer and customer roles.
- Seer dashboard with role overview, queue metrics, priority queue preview, and record metrics.
- Seer profile page with a profile picture mockup, contact detail, activity, edit flow, and logout.
- Customer space with active reading, quick actions, two-column seer discovery cards, seer profile details, mock seer chat, customer profile, and logout.
- Customer coin wallet mockup where THB top-ups add in-app coins, with payment methods including QR payment.
- Seer detail booking mockup with message, book, and coin-based call options for 15 minutes, 30 minutes, or 1 hour.
- Simple generated app icon in the asset catalog.
- Edit Profile includes mock profile picture style selection.
- Shared in-memory test chat store so the customer and seer accounts can exchange messages during API planning.
- Improved mock chat with a customer queue, search, status/priority chips, reading context, quick replies, and seer/customer bubbles.
- Create records with a title and notes.
- Read records in a native SwiftUI list.
- Update records from the edit sheet.
- Delete records from each record action menu.
- Mark records done or active from the record action menu.
- Persist records locally with `UserDefaults`.
- Supabase-ready domain models and data service protocol for users, seer profiles, customer profiles, reading requests, chat threads, messages, and reviews.
- URLSession-based `SupabaseHoroDataService` for test login/auth, `v_my_wallet`, `seer_profile`/`seer_service`, `submit_question`, and `question_message`.
- In-memory `MockHoroDataService` with unit coverage for role login, seer search, reading request CRUD, and chat messages.
- DB-to-app function analysis in `docs/specs/horo-app-function-map.md`.

The CRUD storage is intentionally isolated behind `RecordStoring`, so a Supabase-backed implementation can replace `UserDefaultsRecordStore` later. The broader app data layer is isolated behind `HoroDataServicing`, with both mock and Supabase implementations available.
