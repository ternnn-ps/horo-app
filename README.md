# HoroTest

A simple SwiftUI iOS test app for a mock teller operation workflow. It includes a customer chat queue, teller dashboard, profile screen, local CRUD records, and an XCTest unit test target.

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

## Current Features

- Light Mode and Dark Mode-friendly SwiftUI colors.
- Bottom tab navigation for Chat, Dashboard, and Profile.
- Mock teller and customer operation roles.
- Teller dashboard with role overview, queue metrics, priority queue preview, and record metrics.
- Profile page with a profile picture mockup, contact detail, activity, and edit flow.
- Improved mock chat with a customer queue, search, status/priority chips, customer context, quick replies, and teller/customer bubbles.
- Create records with a title and notes.
- Read records in a native SwiftUI list.
- Update records from the edit sheet.
- Delete records from each record action menu.
- Mark records done or active from the record action menu.
- Persist records locally with `UserDefaults`.

The CRUD storage is intentionally isolated behind `RecordStoring`, so a Supabase-backed implementation can replace `UserDefaultsRecordStore` later.
