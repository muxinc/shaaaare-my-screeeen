#!/bin/bash
set -euo pipefail

# Usage: ./bump.sh [patch|minor|major]
# Defaults to patch (1.0.0 → 1.0.1)

BUMP_TYPE="${1:-patch}"
INFO_PLIST="Resources/Info.plist"

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP_TYPE" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    *)
        echo "Usage: ./bump.sh [patch|minor|major]" >&2
        exit 1
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "Version: $CURRENT_VERSION → $NEW_VERSION"
echo "Build:   $CURRENT_BUILD → $NEW_BUILD"
echo ""

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

git add "$INFO_PLIST"
git commit -m "Bump to $NEW_VERSION"
git tag "v$NEW_VERSION"

echo ""
echo "Ready. Push to trigger the release:"
echo ""
echo "  git push origin main --tags"
