# Signing And Permissions

This app must be launched as a real `.app` bundle with a stable Apple-issued code signature. If you sign ad hoc, sign with a self-signed certificate, or launch `Contents/MacOS/ShaaaareMyScreeeen` directly, macOS can treat each rebuild like a different app for TCC and Keychain purposes.

## Recommended Setup

For local development:

- Prefer an `Apple Development` certificate if you have one.
- If you only have `Developer ID Application`, that is still stable enough for local TCC and Keychain testing.
- Keep the bundle identifier fixed as `com.mux.shaaaare-my-screeeen`.
- Launch with `open dist/ShaaaareMyScreeeen.app`, not by executing the inner Mach-O directly.

For distribution:

- Sign with `Developer ID Application`.
- Use hardened runtime.
- Notarize and staple the finished app.

## First-Time Cleanup After Switching Away From Ad-Hoc Or Self-Signed Builds

Run this once after moving to an Apple-issued identity:

```bash
./run.sh --reset-tcc --reset-keychain
```

That does two things:

- clears stale Camera, Microphone, and ScreenCapture TCC rows created by old signatures
- deletes the two stored Mux credential items so they can be recreated under the new signature

## Normal Development Flow

1. Verify you have an Apple-issued signing identity:

```bash
security find-identity -v -p codesigning
```

2. Build and launch:

```bash
./run.sh
```

3. Grant Camera, Microphone, and Screen Recording once when macOS prompts.

4. Save your Mux credentials again if you ran `--reset-keychain`.

After that, repeat launches should keep the same TCC and Keychain trust as long as:

- the bundle identifier stays the same
- you keep using the same Apple-issued identity family
- you keep launching the `.app` bundle through Launch Services

## Useful Variants

Force Apple Development signing:

```bash
./run.sh --apple-development
```

Force Developer ID signing:

```bash
./run.sh --developer-id
```

Build and sign without launching:

```bash
./run.sh --no-launch
```

## What Not To Add

Do not add `keychain-access-groups` unless you actually need cross-app keychain sharing. That entitlement is restricted on macOS and requires a matching provisioning profile embedded in the app. It is not needed for this app's normal single-app keychain storage.

## Release Checklist

1. Build and sign with Developer ID:

```bash
./run.sh --developer-id --no-launch
```

2. Notarize the app:

```bash
xcrun notarytool submit dist/ShaaaareMyScreeeen.app --wait
```

3. Staple the notarization ticket:

```bash
xcrun stapler staple dist/ShaaaareMyScreeeen.app
```
