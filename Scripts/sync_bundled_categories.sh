#!/usr/bin/env bash
# Refresh the bundled categories.json fallback from CaskKit's latest GitHub release.
#
# Run this before cutting an app release so the bundle ships with up-to-date
# classifications even when remote refresh fails on first launch.
#
# At runtime, CategoryService.refreshFromRemote() also pulls the latest copy,
# so this script is a *fallback* freshness measure, not the primary source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$SCRIPT_DIR/../CaskHub/Resources/categories.json"
URL="https://github.com/alielsokary/CaskKit/releases/latest/download/categories.json"

echo "Fetching $URL"
curl -fsSL "$URL" -o "$DEST"
echo "Updated $DEST"
