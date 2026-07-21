---
name: release-notes
description: Use when cutting a CaskHub release, adding a CHANGELOG.md entry, or drafting the GitHub release body / Sparkle appcast description
---

# CaskHub Release Notes

## Overview

`CHANGELOG.md` at the repo root (Keep a Changelog style: cumulative, newest
first) is the single source. `Scripts/release.sh` extracts the TOP entry and
uses it as both the GitHub release body and the Sparkle update dialog notes
(embedded into `appcast.xml`, rendered as markdown). Feature-PR descriptions are
not covered by this standard — keep them as detailed as you like. The release PR
is the exception (see Release PR description below).

## Format

Each release adds one entry at the top of `CHANGELOG.md`:

```markdown
## x.y.z — YYYY-MM-DD

### What's New

- Bullet per user-visible feature

### Improvements

- Bullet per enhancement to something that already existed

### Bug Fixes

- Bullet per user-visible fix
```

- The top `##` header MUST be the version being cut — `release.sh` aborts on
  mismatch, so forgetting to add the new entry fails loudly.
- Omit any section that would be empty. A patch release may be Bug Fixes only.
- Never rewrite past entries; only add the new one on top.

## Writing the bullets

Source material: `git log --oneline --first-parent <prev-tag>..HEAD` and the
merged PR titles/descriptions since the last release.

- User-facing language: say what changed for the user, not how it was built
  ("Faster search results", not "Refactored CaskRepository query path").
- Start each bullet with a verb (Added / Fixed / Improved…), sentence case,
  no trailing period, one line each.
- Collapse related minor fixes into one bullet; aim for ≤6 bullets a section.
- Never include: back-merge PRs ("master to develop"), version-bump/appcast
  commits ("release: x.y.z"), CI/workflow changes, test-only changes, refactors
  or dependency bumps with no user-visible effect, PR numbers, commit hashes.
- If literally everything in the range is internal, write one honest bullet
  under Improvements ("Under-the-hood stability improvements") rather than
  padding.

## Release PR description

The `release/x.y.z → master` PR body is two parts, in order, and nothing else:

1. **Changelog** — the version's What's New / Improvements / Bug Fixes bullets
   (the same content that ships as the release notes).
2. **Release artifacts** — a short list of what the build produced: the
   notarized zip and build number, the appcast update, the README bump, dSYMs.

Merging behavior lives in the runbook and the publish-release.yml /
sync-develop.yml workflows, not in the PR body.

## Example entry

```markdown
## 0.7.0 — 2026-08-02

### What's New

- Added import and export for your installed app list

### Improvements

- Faster cask search while typing

### Bug Fixes

- Fixed Homebrew repair getting stuck after relaunch
- Fixed update badge showing for already-updated casks
```
