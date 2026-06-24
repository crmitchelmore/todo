# iOS / TestFlight release

Capture ships to TestFlight with **manual signing**: CI installs a reusable Apple Distribution
certificate and existing App Store provisioning profiles from GitHub secrets. Do not use Xcode
automatic provisioning for release uploads; on ephemeral runners it can create new Apple signing
assets and exhaust the account certificate limit.

## Credentials (this machine)
- **Team ID**: `8X4ZN58TYH`
- **API key ID**: `Y6C8R5DA75` → `~/.private_keys/AuthKey_Y6C8R5DA75.p8`
- **Issuer ID**: stored as the GH secret `APP_STORE_CONNECT_ISSUER_ID` (write-only). Export it
  into your shell before running locally.

## Bundle IDs
- `dev.crmitchelmore.capture.ios` — app
- `dev.crmitchelmore.capture.ios.share` — Share extension
- `dev.crmitchelmore.capture.mac` — macOS app

## Apple Developer portal prerequisites

The App Group identifier existing is not enough for TestFlight signing. In **Certificates,
Identifiers & Profiles → Identifiers → App IDs**, both iOS App IDs must have the same group
explicitly assigned:

1. `dev.crmitchelmore.capture.ios` → App Groups → tick `group.dev.crmitchelmore.capture`.
2. `dev.crmitchelmore.capture.ios.share` → App Groups → tick `group.dev.crmitchelmore.capture`.

The Share Extension may also have other groups assigned, but it must include the plain
`group.dev.crmitchelmore.capture` group used by the app entitlement. Creating only
`group.dev.crmitchelmore.capture.ios.share` does not satisfy the extension entitlement.

If Apple invalidates profiles after saving the App Group assignment, rerun the TestFlight workflow;
cloud signing regenerates the required profiles automatically.

## Store validation gotchas

App Store Connect validation is stricter than local simulator builds:

- The 1024x1024 App Store icon must be fully opaque (no alpha channel).
- iPad orientation metadata must include all required iPad orientations, even if the iPhone UI is
  portrait-first.
- The Share Extension bundle version/build must match the containing app's version/build.
- EventKit-linked bundles must include calendar purpose strings (`NSCalendarsUsageDescription` and
  `NSCalendarsFullAccessUsageDescription`) explaining that Capture reads calendar availability to
  suggest realistic due dates and show whether there is time for a task.
- TestFlight export compliance is automated by setting `ITSAppUsesNonExemptEncryption=false` in the
  iOS app, Share extension, and Widget Info.plists. Keep that value unless Capture adds custom or
  non-exempt encryption beyond standard HTTPS/Apple platform security.

## One-time bootstrap (register IDs + create the app record)
```bash
pip install pyjwt cryptography
export APP_STORE_CONNECT_ISSUER_ID=<uuid>
python3 scripts/appstore-bootstrap.py
```
If app creation via API is blocked by your account role/agreement, create the app once in the
App Store Connect UI (Apps → +) with bundle ID `dev.crmitchelmore.capture.ios`; the bundle-ID
registration still runs fine via the script.

## Local release
```bash
export APP_STORE_CONNECT_ISSUER_ID=<uuid>
bash scripts/ios-testflight.sh
```
Defaults: key `Y6C8R5DA75`, team `8X4ZN58TYH`, version from `./VERSION`, build = unix timestamp.

## CI release
Run the **Release iOS (TestFlight)** workflow (`workflow_dispatch`). Required repo secrets:
- `APP_STORE_CONNECT_API_KEY` — base64 of the `.p8`
- `APP_STORE_CONNECT_KEY_ID` — `Y6C8R5DA75`
- `APP_STORE_CONNECT_ISSUER_ID` — issuer UUID
- `APPLE_TEAM_ID` — `8X4ZN58TYH`
- `IOS_DISTRIBUTION_CERTIFICATE` — base64 of an existing Apple Distribution `.p12`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` — password for that `.p12`
- `IOS_APP_STORE_PROFILE` — base64 of the existing App Store profile for `dev.crmitchelmore.capture.ios`
- `IOS_SHARE_APP_STORE_PROFILE` — base64 of the existing App Store profile for `dev.crmitchelmore.capture.ios.share`
- `IOS_WIDGET_APP_STORE_PROFILE` — base64 of the existing App Store profile for `dev.crmitchelmore.capture.ios.widget`

Set the base64 key with:
```bash
gh secret set APP_STORE_CONNECT_API_KEY --body "$(base64 -i ~/.private_keys/AuthKey_Y6C8R5DA75.p8)"
gh secret set APP_STORE_CONNECT_KEY_ID --body Y6C8R5DA75
gh secret set APPLE_TEAM_ID --body 8X4ZN58TYH
gh secret set APP_STORE_CONNECT_ISSUER_ID --body <uuid>
```

Set reusable signing assets by exporting/downloading **existing** assets, not creating new ones:

```bash
gh secret set IOS_DISTRIBUTION_CERTIFICATE --body "$(base64 -i AppleDistribution.p12)"
gh secret set IOS_DISTRIBUTION_CERTIFICATE_PASSWORD --body "<p12-password>"
gh secret set IOS_APP_STORE_PROFILE --body "$(base64 -i Capture_AppStore.mobileprovision)"
gh secret set IOS_SHARE_APP_STORE_PROFILE --body "$(base64 -i CaptureShare_AppStore.mobileprovision)"
gh secret set IOS_WIDGET_APP_STORE_PROFILE --body "$(base64 -i CaptureWidget_AppStore.mobileprovision)"
```
