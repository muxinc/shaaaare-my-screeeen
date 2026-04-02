# Shaaaare My Screeeen

A lightweight, native macOS screen recorder that uploads directly to [Mux](https://mux.com). Lives in your menu bar, records your screen/camera/mic, and gives you a shareable link in seconds.

Built with Swift, SwiftUI, ScreenCaptureKit, and AVFoundation. No Electron, no webviews, no sidecar processes.

## Features

- Record any display or individual window
- Camera overlay (picture-in-picture) with drag positioning
- System audio + microphone capture
- 3-2-1 countdown before recording
- In-app review with playback before uploading
- Direct upload to Mux with progress tracking
- Auto-generated captions (English)
- AI-powered video summaries via Mux Robots API
- Recording library with thumbnails, summaries, and tags
- MCP server for Claude Code integration
- Auto-updates via Sparkle
- Menu bar app — stays out of your way

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 5.10+
- A [Mux](https://mux.com) account with an API access token

## Quick Start

```bash
git clone https://github.com/muxinc/shaaaare-my-screeeen.git
cd shaaaare-my-screeeen
./run.sh
```

That's it. The script builds both the app and the MCP server, bundles them into an `.app`, signs it, and launches it.

On first launch, macOS will prompt you to grant screen recording, camera, and microphone permissions. Enter your Mux API token ID and secret in Settings.

## Building

### Using run.sh (recommended)

```bash
./run.sh              # Build, sign, and launch
./run.sh --no-launch  # Build and sign only
./run.sh --help       # See all options
```

### Using Xcode

```bash
open Package.swift
```

Xcode will handle signing automatically with your Apple ID. Select the `ShaaaareMyScreeeen` scheme and run.

### Using swift build directly

```bash
swift build                        # Build the app
swift build --product shaaaare-mcp # Build the MCP server
```

Note: `swift build` compiles the binary but doesn't create the `.app` bundle needed for permissions to work. Use `run.sh` or Xcode for a complete build.

## Code Signing

macOS requires a signed `.app` bundle for screen recording, camera, and microphone access. The build script handles this automatically:

| You have | What happens | Permissions persist across rebuilds? |
|----------|-------------|--------------------------------------|
| Apple Developer Program membership | Signs with your Developer ID or Apple Development certificate | Yes |
| Free Apple ID added to Xcode | Signs with your development certificate | Yes |
| Nothing | Falls back to ad-hoc signing | No — you'll re-grant permissions each rebuild |

**To get persistent permissions without a paid developer account:**

1. Open Xcode and sign in with your Apple ID (Xcode > Settings > Accounts)
2. This creates a free development certificate on your machine
3. `run.sh` will automatically find and use it

You can also specify a signing identity explicitly:

```bash
./run.sh --identity "Apple Development: you@example.com"
# or
SIGN_IDENTITY="Apple Development: you@example.com" ./run.sh
```

### Troubleshooting permissions

If permissions get stuck or you want a clean slate:

```bash
./run.sh --reset-tcc        # Reset camera/mic/screen recording permissions
./run.sh --reset-keychain   # Clear stored Mux credentials
```

## Project Structure

```
Sources/
├── App/
│   ├── ShaaaareMyScreeenApp.swift    # Entry point, AppDelegate
│   ├── MenuBarController.swift        # Status bar icon + panel management
│   ├── AppState.swift                 # App state, screen routing, upload flow
│   ├── Views/                         # SwiftUI views
│   ├── Recording/                     # ScreenCaptureKit + AVFoundation
│   ├── Mux/                           # Mux API client + models
│   └── Utilities/                     # Keychain, preferences, history, MCP setup
└── MCP/
    └── main.swift                     # Standalone MCP server for Claude Code
```

## MCP Server

The app includes an [MCP](https://modelcontextprotocol.io) server that lets [Claude Code](https://docs.anthropic.com/en/docs/claude-code) access your recording library.

Set it up from Settings in the app (one-click), or manually:

```bash
claude mcp add --transport stdio shaaaare-my-screeeen -- /path/to/dist/ShaaaareMyScreeeen.app/Contents/MacOS/shaaaare-mcp
```

Available tools:

- **list_recordings** — Search and filter recordings by date, title, tags, or keywords
- **get_recording** — Get full details for a recording (playback URL, summary, thumbnail, tags)

Example: _"Find my recording from today and create a GitHub issue with the playback link in the description."_

## Configuration

All configuration is stored locally on your machine:

| What | Where |
|------|-------|
| Mux credentials | macOS Keychain (`com.mux.shaaaare-my-screeeen`) |
| Preferences | UserDefaults |
| Recording history | `~/Library/Application Support/com.mux.shaaaare-my-screeeen/history.json` |
| App logs | `~/Library/Logs/ShaaaareMyScreeeen/app.log` |

## Releasing

The app uses [Sparkle](https://sparkle-project.org) for auto-updates. Users get notified of new versions and can update in-app.

### Publishing a new release

```bash
./bump.sh          # 1.0.0 → 1.0.1 (patch)
git push origin main --tags
```

That's it. GitHub Actions builds, signs, notarizes, and publishes the release. The appcast is updated automatically so existing users see the update.

For minor or major bumps:

```bash
./bump.sh minor    # 1.0.1 → 1.1.0
./bump.sh major    # 1.1.0 → 2.0.0
```

### What happens on push

1. GitHub Actions builds a release binary
2. Signs it with the Developer ID certificate
3. Submits to Apple for notarization and staples the ticket
4. Signs the zip with Sparkle's EdDSA key
5. Creates a GitHub Release with the zip attached
6. Updates the [appcast](https://muxinc.github.io/shaaaare-my-screeeen/appcast.xml) on GitHub Pages

### Local release builds

To build a signed release locally without CI:

```bash
./release.sh --skip-notarize                                    # Signed only
./release.sh --notarize --notary-profile ShaaaareMyScreeeenNotary  # Signed + notarized
```

Output goes to `release/ShaaaareMyScreeeen-macOS.zip`.

## License

MIT. See [LICENSE](LICENSE).
