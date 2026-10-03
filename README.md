# AdMob Revenue Viewer

A native iOS dashboard for viewing AdMob revenue and performance metrics across accounts, apps, ad units, countries, and time periods.

Built with SwiftUI, the app pairs Google Sign-In with the AdMob and AdSense APIs, and includes a home-screen widget for at-a-glance revenue updates.

## Highlights

- Google Sign-In with secure credential storage
- Revenue, impressions, eCPM, CTR, and match-rate reporting
- Account, app, ad-unit, and country breakdowns
- Interactive earnings trends and 12-month history
- Configurable iOS widget with background refresh
- Guest mode backed by sample data for exploring the interface

## Tech stack

- Swift and SwiftUI
- Swift Charts and WidgetKit
- Google Sign-In for iOS
- AdMob API and AdSense API
- Swift Package Manager

## Getting started

1. Clone the repository and open `AdmobTracker.xcodeproj` in Xcode.
2. Select the `AdmobTracker` scheme and allow Swift Package Manager to resolve dependencies.
3. Copy `AdmobTracker/GoogleService-Info.example.plist` to `AdmobTracker/GoogleService-Info.plist`.
4. Replace the placeholder values with your Firebase / Google OAuth configuration.
5. Build and run on an iOS simulator or device.

> `GoogleService-Info.plist` is intentionally excluded from version control because it contains project-specific configuration. Restrict any deployed Google API keys to the app's bundle identifier.

## Project structure

```
AdmobTracker/
  Models/        API response and domain models
  Services/      Authentication, API clients, and widget refresh
  ViewModels/    Presentation state and reporting logic
  Views/         SwiftUI screens and reusable components
Widget/          WidgetKit extension
```

## Privacy

The app uses Google Sign-In only to access the AdMob data authorized by the signed-in user. Credentials are stored locally in the Keychain and are not committed to this repository.
