#!/bin/bash
# Uploads an archive's dSYMs to Sentry so crash reports symbolicate.
# Run manually after archiving a release (no release pipeline exists yet):
#   SENTRY_AUTH_TOKEN=... SENTRY_ORG=... SENTRY_PROJECT=... \
#     ./Scripts/upload_dsyms.sh ~/path/to/CaskHub.xcarchive
set -euo pipefail

archive="${1:?usage: upload_dsyms.sh <path-to-.xcarchive>}"
dsyms="$archive/dSYMs"

command -v sentry-cli >/dev/null 2>&1 || {
    echo "error: sentry-cli not found — brew install getsentry/tools/sentry-cli" >&2
    exit 1
}
: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN is not set}"
: "${SENTRY_ORG:?SENTRY_ORG is not set}"
: "${SENTRY_PROJECT:?SENTRY_PROJECT is not set}"
[ -d "$dsyms" ] || {
    echo "error: no dSYMs directory inside $archive" >&2
    exit 1
}

sentry-cli debug-files upload --org "$SENTRY_ORG" --project "$SENTRY_PROJECT" "$dsyms"
