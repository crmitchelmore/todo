# macOS releases & auto-updates (Sparkle)

The Capture Mac app ships outside the App Store with [Sparkle](https://sparkle-project.org)
auto-updates, mirroring the `justspeaktoit` setup.

## How it works

- The app embeds Sparkle (SPM, 2.6.0) via `clients/apps/project.yml`.
- `UpdaterController` starts `SPUStandardUpdaterController` at launch, which performs
  scheduled background checks (every `SUScheduledCheckInterval` = 86400s). The app menu
  has **Check for Updates…** for on-demand checks.
- Sparkle reads the appcast from `SUFeedURL`:
  `https://github.com/crmitchelmore/todo/releases/latest/download/appcast.xml`.
  GitHub's `releases/latest/download/<asset>` always resolves to the newest published
  release's asset, so no separate hosting is needed.
- Each update archive (`Capture-<version>.zip`) is signed with an EdDSA key; the matching
  public key is baked into Info.plist as `SUPublicEDKey`.

## Signing keys

- EdDSA keypair generated with Sparkle's `generate_keys --account capture`.
- Public key (in Info.plist): `HRZfphOJCk8UJTLcguwmJ+BL0ynRJGkiVAZpnsrk1RU=`.
- Private key lives in the macOS keychain (account `capture`) and as the GitHub Actions
  secret `SPARKLE_PRIVATE_KEY`. **Never commit it.**

## Cutting a release

Push a tag:

```bash
git tag mac-v0.1.0
git push origin mac-v0.1.0
```

The **Release macOS App** workflow (`.github/workflows/release-mac.yml`) then:

1. Generates the Xcode project (XcodeGen) and stamps version + build number.
2. Archives `CaptureMac` with hardened runtime.
3. Exports + signs for **Developer ID** using the App Store Connect API key.
4. Notarises with `notarytool` (API key) and staples the ticket.
5. Zips the stapled app, generates a signed `appcast.xml`.
6. Publishes `Capture-<version>.zip` + `appcast.xml` as GitHub release assets.

### Required secrets

Already configured: `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, `APPLE_TEAM_ID`, `SPARKLE_PRIVATE_KEY`.

### Developer ID certificate (required)

Developer ID signing requires a **Developer ID Application** certificate + private key
in the runner keychain — the App Store Connect API key alone cannot create one, so the
workflow fails fast if these secrets are absent. Add:

- `APPLE_DEVELOPER_ID_APPLICATION` — base64 of a `.p12` containing the Developer ID
  Application cert + private key.
- `APPLE_DEVELOPER_ID_APPLICATION_PASSWORD` — the `.p12` password.

To create the `.p12` locally from your keychain: export the "Developer ID Application"
identity from Keychain Access, then `base64 -i cert.p12 | pbcopy`. (If you don't yet have
a Developer ID Application cert, create one in the Apple Developer portal → Certificates.)

## Feed URL constraint

`releases/latest/download/appcast.xml` resolves to the repo's latest non-prerelease
release. Keep the **Mac release the only GitHub Release type** that publishes (iOS ships
via TestFlight, not GitHub Releases), so `/latest/` always carries a current `appcast.xml`.
If you later add other GitHub Releases, host the appcast at a fixed URL instead.
