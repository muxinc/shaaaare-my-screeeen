#!/bin/bash
set -euo pipefail

APP_NAME="ShaaaareMyScreeeen"
SOURCE_BUILD_DIR=".build/debug"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="Resources/Info.plist"
ENTITLEMENTS="Resources/ShaaaareMyScreeeen.entitlements"
LOG_FILE="$HOME/Library/Logs/$APP_NAME/app.log"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")
KEYCHAIN_SERVICE="$BUNDLE_ID"

IDENTITY_MODE="auto"
SIGN_IDENTITY_OVERRIDE="${SIGN_IDENTITY:-}"
NO_LAUNCH=0
RESET_TCC=0
RESET_KEYCHAIN=0
LAUNCH_ARGS=()

usage() {
    cat <<EOF
Usage: ./run.sh [options] [-- app-args...]

Options:
  --apple-development  Prefer an Apple Development identity for local dev
  --developer-id       Prefer a Developer ID Application identity
  --identity NAME      Use the provided signing identity or SHA-1 hash
  --reset-tcc          Reset Camera, Microphone, and ScreenCapture TCC state once
  --reset-keychain     Delete stored Mux keychain items once
  --no-launch          Build, sign, and verify the app without launching it
  --help               Show this help

Environment:
  SIGN_IDENTITY        Override the signing identity without passing --identity
EOF
}

find_identity() {
    local label="$1"
    security find-identity -v -p codesigning | awk -F '"' -v label="$label" '$0 ~ label { print $2; exit }'
}

resolve_sign_identity() {
    if [[ -n "$SIGN_IDENTITY_OVERRIDE" ]]; then
        printf '%s\n' "$SIGN_IDENTITY_OVERRIDE"
        return
    fi

    case "$IDENTITY_MODE" in
        apple-development)
            find_identity "Apple Development"
            ;;
        developer-id)
            find_identity "Developer ID Application"
            ;;
        auto)
            local identity
            identity="$(find_identity "Apple Development" || true)"
            if [[ -n "$identity" ]]; then
                printf '%s\n' "$identity"
                return
            fi
            find_identity "Developer ID Application"
            ;;
        *)
            return 1
            ;;
    esac
}

reset_tcc() {
    local service="$1"
    tccutil reset "$service" "$BUNDLE_ID" >/dev/null || true
    echo "Reset $service permission for $BUNDLE_ID"
}

reset_app_permission_state() {
    defaults delete "$BUNDLE_ID" "ScreenPermissionRequestedFromUI" >/dev/null 2>&1 || true
    echo "Cleared app-managed screen permission request state for $BUNDLE_ID"
}

delete_keychain_item() {
    local account="$1"
    security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" >/dev/null 2>&1 || true
    echo "Deleted keychain item: service=$KEYCHAIN_SERVICE account=$account"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apple-development)
            IDENTITY_MODE="apple-development"
            shift
            ;;
        --developer-id)
            IDENTITY_MODE="developer-id"
            shift
            ;;
        --identity)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --identity" >&2
                exit 1
            fi
            SIGN_IDENTITY_OVERRIDE="$2"
            shift 2
            ;;
        --reset-tcc)
            RESET_TCC=1
            shift
            ;;
        --reset-keychain)
            RESET_KEYCHAIN=1
            shift
            ;;
        --no-launch)
            NO_LAUNCH=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        --)
            shift
            LAUNCH_ARGS+=("$@")
            break
            ;;
        *)
            LAUNCH_ARGS+=("$1")
            shift
            ;;
    esac
done

swift build
swift build --product shaaaare-mcp

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

cp "$SOURCE_BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
cp "$SOURCE_BUILD_DIR/shaaaare-mcp" "$MACOS/shaaaare-mcp"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"

if [[ -d "Resources/AppIcon.appiconset" ]]; then
    cp -r "Resources/AppIcon.appiconset" "$RESOURCES/"
fi

if [[ -d "$SOURCE_BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]]; then
    cp -r "$SOURCE_BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$RESOURCES/"
fi

# Embed Sparkle.framework
FRAMEWORKS="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS"
SPARKLE_FW="$SOURCE_BUILD_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    cp -R "$SPARKLE_FW" "$FRAMEWORKS/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME" 2>/dev/null || true
fi

SIGN_IDENTITY="$(resolve_sign_identity || true)"
if [[ -n "$SIGN_IDENTITY" ]]; then
    SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
    if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
        SIGN_ARGS+=(--options runtime --timestamp)
    fi

    # Sign Sparkle framework components (inner to outer)
    if [[ -d "$FRAMEWORKS/Sparkle.framework" ]]; then
        for component in "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/"*.xpc \
                         "$FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app"; do
            [[ -e "$component" ]] && codesign "${SIGN_ARGS[@]}" "$component"
        done
        codesign "${SIGN_ARGS[@]}" "$FRAMEWORKS/Sparkle.framework"
    fi

    # Sign MCP binary
    codesign "${SIGN_ARGS[@]}" "$MACOS/shaaaare-mcp"

    # Sign the app bundle (with entitlements)
    if [[ -f "$ENTITLEMENTS" ]]; then
        codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
    else
        codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
    fi
    echo "Signed with: $SIGN_IDENTITY"
else
    codesign --force --sign - "$APP_BUNDLE"
    echo "Warning: No Apple-issued signing identity found; using ad-hoc signing."
    echo "TCC and keychain access will not persist reliably across rebuilds."
fi

codesign --verify --strict --verbose=2 "$APP_BUNDLE"

echo "Signature summary:"
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Authority=|Runtime Version=' || true

echo "Designated requirement:"
codesign -d -r- "$APP_BUNDLE" 2>&1 | sed '1d'

if (( RESET_TCC )); then
    reset_tcc "Camera"
    reset_tcc "Microphone"
    reset_tcc "ScreenCapture"
    reset_app_permission_state
fi

if (( RESET_KEYCHAIN )); then
    delete_keychain_item "mux-token-id"
    delete_keychain_item "mux-token-secret"
fi

echo "Built $APP_BUNDLE"
echo "Bundle ID: $BUNDLE_ID"
echo "App log: $LOG_FILE"

if (( NO_LAUNCH )); then
    exit 0
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

echo "Launching via Launch Services... (close the app to stop log tailing)"
tail -n 0 -F "$LOG_FILE" &
TAIL_PID=$!

cleanup() {
    kill "$TAIL_PID" >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

if (( ${#LAUNCH_ARGS[@]} > 0 )); then
    open -W -n "$APP_BUNDLE" --args "${LAUNCH_ARGS[@]}"
else
    open -W -n "$APP_BUNDLE"
fi
