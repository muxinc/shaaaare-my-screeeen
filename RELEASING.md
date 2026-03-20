# Releasing

This project uses two separate scripts:

- `./run.sh` for local development
- `./release.sh` for a shareable app build

## Prerequisites

- an Apple-issued signing identity in your keychain
- `Developer ID Application` for builds you want to share outside your machine
- `notarytool` credentials stored locally if you want notarization

Check available signing identities:

```bash
security find-identity -v -p codesigning
```

## Build A Shareable App

Build a signed release app and a zip artifact:

```bash
./release.sh --skip-notarize
```

Artifacts land in `release/`:

- `release/ShaaaareMyScreeeen.app`
- `release/ShaaaareMyScreeeen-macOS.zip`

This is enough for quick internal testing, but macOS will give recipients a rougher first-run experience unless the app is notarized.

## Build A Notarized App

Store a notary profile once:

```bash
xcrun notarytool store-credentials "ShaaaareMyScreeeenNotary" \
  --apple-id "<APPLE_ID>" \
  --team-id "<TEAM_ID>" \
  --password "<APP_SPECIFIC_PASSWORD>"
```

Then build, notarize, staple, and zip:

```bash
./release.sh --notarize --notary-profile ShaaaareMyScreeeenNotary
```

## Recommended Handoff For Nontechnical Teammates

1. Upload the notarized zip to a GitHub Release.
2. Ask them to download and drag the app into `Applications`.
3. On first run, have them click the permission rows one at a time:
   - `Screen Recording`
   - `Camera`
   - `Microphone`
4. Have them enter their Mux credentials in Settings.

## Open Source Notes

- Do not commit Apple certificates, private keys, or provisioning profiles.
- Do not commit Mux tokens.
- If you later automate releases in GitHub Actions, put signing and notarization credentials in repository or organization secrets.
