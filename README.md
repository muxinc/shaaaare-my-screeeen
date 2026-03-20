# shaaaare-my-screeeen

A lightweight Loom replacement for macOS. Records screen, camera, and audio, then uploads directly to Mux.

Uploads require your own Mux API access token and secret, entered locally in the app and stored in the macOS Keychain.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.10+
- A Mux account (access token + secret key)

## Build & Run

```bash
./run.sh
```

This builds the project, signs it with an Apple-issued identity when available, and launches it as a proper `.app` bundle through Launch Services.

If you are switching from older ad-hoc or self-signed builds, do one cleanup run first:

```bash
./run.sh --reset-tcc --reset-keychain
```

That clears stale TCC state and deletes old Mux keychain items created under the wrong signature.

Or open in Xcode:

```bash
open Package.swift
```

Detailed setup notes live in [docs/signing-and-permissions.md](docs/signing-and-permissions.md).

## Share A Build

For nontechnical teammates, do not send the source tree. Build a signed release artifact instead:

```bash
./release.sh --skip-notarize
```

For the full distribution flow, including notarization and stapling, see [RELEASING.md](RELEASING.md).

## Features

- Display or window capture via ScreenCaptureKit
- Camera overlay (circular, draggable) composited into recording
- System audio + microphone capture
- 3-2-1 countdown before recording
- Floating stop control during recording
- In-app review with AVPlayer before uploading
- Direct upload to Mux with progress tracking
- Credentials stored securely in macOS Keychain

## License

MIT. See [LICENSE](LICENSE).
