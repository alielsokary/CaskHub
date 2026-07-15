#!/usr/bin/env bash
# Release pipeline: archive → Developer ID export → notarize → staple → zip →
# appcast → GitHub release. Requires: Developer ID cert in Keychain, notarytool
# keychain profile "caskhub-notary", gh CLI authenticated.
#
# Usage: Scripts/release.sh <version>   e.g. Scripts/release.sh 1.0.0
set -euo pipefail

VERSION="${1:?usage: Scripts/release.sh <version> (e.g. 1.0.0)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$REPO_ROOT/.build/release"
NOTARY_PROFILE="caskhub-notary"
TEAM_ID="USYCM7BRK3"
SPARKLE_VERSION="2.9.4"
DOWNLOAD_URL_PREFIX="https://github.com/alielsokary/CaskHub/releases/download/v$VERSION/"

cd "$REPO_ROOT"

# --- Preflight ---------------------------------------------------------------
BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != release/* ]]; then
    echo "error: releases are cut from release/* branches (current: $BRANCH)" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree not clean — commit or stash first" >&2
    exit 1
fi

echo "==> Syncing bundled categories"
Scripts/sync_bundled_categories.sh
if [[ -n "$(git status --porcelain CaskHub/Resources/categories.json)" ]]; then
    echo "error: categories.json was stale. Commit the refreshed copy, then rerun." >&2
    exit 1
fi

# Monotonic build number for Sparkle's CFBundleVersion comparison.
BUILD_NUMBER="$(git rev-list --count HEAD)"
echo "==> Version $VERSION (build $BUILD_NUMBER)"

rm -rf "$WORK"
mkdir -p "$WORK/updates"

# --- Archive & export with Developer ID --------------------------------------
echo "==> Archiving"
xcodebuild -project CaskHub.xcodeproj -scheme CaskHub -configuration Release \
    archive -archivePath "$WORK/CaskHub.xcarchive" \
    -derivedDataPath "$WORK/DerivedData" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    | tail -5

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Exporting with Developer ID signing"
xcodebuild -exportArchive -archivePath "$WORK/CaskHub.xcarchive" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" \
    -exportPath "$WORK/export" | tail -5

APP="$WORK/export/CaskHub.app"

# --- Notarize & staple --------------------------------------------------------
echo "==> Notarizing (this can take a few minutes)"
ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
xcrun notarytool submit "$WORK/notarize.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP"

# --norsrc/--noextattr/--noqtn: keep AppleDouble (._*) entries out of the zip —
# some unzippers write them as literal files inside the signed bundle and
# Gatekeeper then rejects it as "unsealed contents".
ZIP="$WORK/updates/CaskHub-$VERSION.zip"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$ZIP"

# --- Appcast ------------------------------------------------------------------
# ponytail: appcast lists only the latest version — enough for Sparkle to offer
# the update; add archive history if delta updates ever matter.
GENERATE_APPCAST="$(find "$WORK/DerivedData/SourcePackages" -name generate_appcast -type f -perm +111 2>/dev/null | head -1 || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
    echo "==> generate_appcast not in SPM artifacts; downloading Sparkle $SPARKLE_VERSION dist"
    curl -fsSL -o "$WORK/sparkle.tar.xz" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    mkdir -p "$WORK/sparkle-dist"
    tar -xf "$WORK/sparkle.tar.xz" -C "$WORK/sparkle-dist"
    GENERATE_APPCAST="$WORK/sparkle-dist/bin/generate_appcast"
fi

echo "==> Generating appcast (signs with EdDSA key from Keychain)"
"$GENERATE_APPCAST" --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$WORK/updates"
cp "$WORK/updates/appcast.xml" "$REPO_ROOT/appcast.xml"

# --- Publish ------------------------------------------------------------------
echo "==> Creating GitHub release v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "CaskHub v$VERSION" --generate-notes \
    --target "$(git rev-parse HEAD)"

echo "==> Committing appcast"
git add appcast.xml
git commit -m "release: v$VERSION appcast"
git push

echo "==> Done. v$VERSION is live; Sparkle clients will see it via appcast.xml."
