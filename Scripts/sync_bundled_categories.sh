#!/usr/bin/env bash
# Refresh the bundled CaskFlow fallbacks from its latest GitHub release.
#
# Run this before cutting an app release so the bundle ships with up-to-date
# classifications and first-seen dates even when remote refresh fails on launch.
#
# At runtime, CategoryService.refreshFromRemote() also pulls the latest copy,
# so this script is a *fallback* freshness measure, not the primary source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="$SCRIPT_DIR/../CaskHub/Resources"
BASE_URL="https://github.com/alielsokary/CaskFlow/releases/latest/download"

for asset in categories.json added_dates.json; do
    destination="$RESOURCE_DIR/$asset"
    temporary="$destination.download"
    echo "Fetching $BASE_URL/$asset"
    curl -fsSL "$BASE_URL/$asset" -o "$temporary"
    mv "$temporary" "$destination"
    echo "Updated $destination"
done
