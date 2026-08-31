---
tags: [chataa, build, xcode, ios, device]
status: active
updated: 2026-08-29
---

# Chataa Build and Device Notes

Hub: [[Chataa]]

## Current iOS Target

- Minimum deployment target: iOS 26.1.
- Current Xcode SDK in logs may show iPhoneOS26.2 because that is the installed SDK.
- Build target still uses `arm64-apple-ios26.1`.

## Important Device Rule

Do not run iOS Simulator on this Mac during development. It has caused the machine to freeze.

Use physical-device or generic iOS builds only.

## Safe Verification Commands

Type-check Swift files for iOS 26.1:

```sh
xcrun --sdk iphoneos swiftc -parse-as-library -typecheck -target arm64-apple-ios26.1 $(rg --files HoroTest -g '*.swift')
```

Build for generic physical iOS target:

```sh
xcodebuild -project HoroTest.xcodeproj -scheme HoroTest -destination 'generic/platform=iOS' build
```

## Common Xcode Notes

If Xcode says a newer iOS runtime must be installed, check whether the selected destination is a simulator runtime. For the real iPhone on iOS 26.1, use the connected device as the run destination.

If `HoloTest.xcodeproj does not exist`, the project name is currently:

```text
HoroTest.xcodeproj
```

If Xcode logs mention `iPhoneOS26.2.sdk`, that is the SDK used by Xcode. It does not mean the app deployment target changed from iOS 26.1.

## Current Signing

The current app bundle id is:

```text
com.pacharapol.HoroTest
```

Changing to Chataa should be planned carefully because bundle id affects device installs, TestFlight, push notifications, and IAP product setup.
