---
name: release-notes
description: Use when cutting a CaskHub release, writing or reviewing RELEASE_NOTES.md, or drafting the GitHub release body / Sparkle appcast description
---

# CaskHub Release Notes

## Overview

One file — `RELEASE_NOTES.md` at the repo root — is the single source for both
the GitHub release body and the Sparkle update dialog. `Scripts/release.sh`
embeds it into `appcast.xml` (Sparkle renders the markdown) and passes it to
`gh release create --notes-file`. PR descriptions are NOT covered by this
standard: keep them as detailed as you like.

## Format

```markdown
<!-- release: x.y.z -->
## What's New

- Bullet per user-visible feature

## Improvements

- Bullet per enhancement to something that already existed

## Bug Fixes

- Bullet per user-visible fix
```

- The first line MUST be `<!-- release: x.y.z -->` with the exact version being
  cut — `release.sh` greps for it and aborts on mismatch, so a stale file from
  the previous release fails loudly. The comment is invisible on GitHub and is
  stripped before the appcast embed.
- Omit any section that would be empty. A patch release may be Bug Fixes only.

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

## Example

```markdown
<!-- release: 0.7.0 -->
## What's New

- Added import and export for your installed app list

## Improvements

- Faster cask search while typing

## Bug Fixes

- Fixed Homebrew repair getting stuck after relaunch
- Fixed update badge showing for already-updated casks
```
