#!/bin/bash
set -euo pipefail

APP_NAME="ShaaaareMyScreeeen"
CONFIGURATION="release"
SOURCE_BUILD_DIR=".build/$CONFIGURATION"
OUTPUT_DIR="release"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="Resources/Info.plist"
ENTITLEMENTS="Resources/ShaaaareMyScreeeen.entitlements"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-macOS.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SHOULD_NOTARIZE=0
SIGN_IDENTITY_OVERRIDE="${SIGN_IDENTITY:-}"

usage() {
    cat <<EOF
Usage: ./release.sh [options]

Options:
  --identity NAME             Use the provided signing identity or SHA-1 hash
  --notarize                  Submit the signed app for notarization and staple it
  --notary-profile NAME       notarytool keychain profile name
  --skip-notarize             Build and sign only
  --help                      Show this help

Environment:
  SIGN_IDENTITY               Override the signing identity
  NOTARY_PROFILE              Default notarytool keychain profile name
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

    find_identity "Developer ID Application"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --identity" >&2
                exit 1
            fi
            SIGN_IDENTITY_OVERRIDE="$2"
            shift 2
            ;;
        --notarize)
            SHOULD_NOTARIZE=1
            shift
            ;;
        --notary-profile)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --notary-profile" >&2
                exit 1
            fi
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --skip-notarize)
            SHOULD_NOTARIZE=0
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

SIGN_IDENTITY="$(resolve_sign_identity || true)"
if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "A Developer ID Application certificate is required for release builds." >&2
    exit 1
fi

if (( SHOULD_NOTARIZE )) && [[ -z "$NOTARY_PROFILE" ]]; then
    echo "--notarize requires --notary-profile or NOTARY_PROFILE" >&2
    exit 1
fi

swift build -c "$CONFIGURATION"

rm -rf "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p "$MACOS" "$RESOURCES"

cp "$SOURCE_BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"

if [[ -d "Resources/AppIcon.appiconset" ]]; then
    cp -r "Resources/AppIcon.appiconset" "$RESOURCES/"
fi

if [[ -d "$SOURCE_BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]]; then
    cp -r "$SOURCE_BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$RESOURCES/"
fi

codesign --force \
    --sign "$SIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
spctl -a -vv -t execute "$APP_BUNDLE" || true

ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if (( SHOULD_NOTARIZE )); then
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    xcrun stapler staple "$APP_BUNDLE"

    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
fi

echo "Built release artifact:"
echo "  $APP_BUNDLE"
echo "  $ZIP_PATH"
