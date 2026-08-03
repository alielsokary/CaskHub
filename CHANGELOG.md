# Changelog

User-facing changes to CaskHub, newest first. The top entry becomes the GitHub
release body and the Sparkle update dialog notes (see `.claude/skills/release-notes`).
Releases before 0.6.4 are on the [releases page](https://github.com/alielsokary/CaskHub/releases).

## 0.6.9 — 2026-08-03

### What's New

- Added an Updates tab in Settings with manual update checks and last-check status
- Added a support card in About that links straight to the issue reporter

### Improvements

- Smoother scrolling while installs and downloads are running
- Faster search with instant typing echo and quicker name sorting
- Faster app launch on large catalogs
- Long lists now load in chunks as you scroll instead of all at once
- Clearer error messages when an install or update fails
- Catalog loading retries automatically when the Homebrew server has a hiccup

### Bug Fixes

- Fixed the Update button appearing for apps Homebrew no longer considers installed
- Fixed a crash risk in the main-menu update command

## 0.6.8 — 2026-07-31

### What's New

- Catalog now refreshes automatically when you return to the app

### Improvements

- New casks appear in Recently Added as soon as Homebrew publishes them
- Recently Added now orders same-day casks by exact publish time
- Fewer UI freezes while browsing, scrolling, and during installs

### Bug Fixes

- Fixed icons for newly published casks staying hidden for up to a day

## 0.6.7 — 2026-07-29

### What's New

- Added a confirmation before Update All that shows how many apps will be updated
- Added a confirmation before quitting while Homebrew operations are running

### Improvements

- Closing the window now quits CaskHub
- App info now shows installed and last-updated dates plus category details

### Bug Fixes

- Fixed some package-installed apps with variant names not being detected as launchable

## 0.6.6 — 2026-07-26

### Improvements

- Faster and smoother catalog browsing, scrolling, and sidebar navigation
- Catalog keeps your scroll position when switching layouts
- Refined the action controls in list view

### Bug Fixes

- Fixed download status not distinguishing already-cached downloads from active ones

## 0.6.5 — 2026-07-24

### What's New

- Added live download progress with downloaded and total sizes to install, adopt, and update controls
- Added passive operation status for individual, concurrent, and Update All tasks
- Added detection and safe adoption for apps installed through the App Store, installer packages, or outside Homebrew
- Added Recently Installed sorting for installed apps and made it the default

### Improvements

- Improved Adopt and Updates ordering to default to Name A–Z
- Improved download progress with clear phase transitions, stable text, and smoother movement

### Bug Fixes

- Fixed same-named apps showing incorrect Adopt actions by resolving ownership through bundle identity
- Fixed external apps in localized or nested application folders not being recognized

## 0.6.4 — 2026-07-21

### What's New

- Update notifications now appear at launch so you can see what's new before installing
- Added a setting to turn the launch notification off and keep updates fully silent

### Bug Fixes

- Fixed Repair stopping before reinstalling when Homebrew failed during cleanup after the app was already removed
- Fixed Repair uninstalls removing unrelated dependencies
