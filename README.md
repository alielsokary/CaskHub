# CaskHub

[![Tests](https://github.com/alielsokary/CaskHub/actions/workflows/tests.yml/badge.svg?branch=develop)](https://github.com/alielsokary/CaskHub/actions/workflows/tests.yml)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/b2d4203ef8724bc0a2265af613ac29c9)](https://app.codacy.com/gh/alielsokary/CaskHub/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![codecov](https://codecov.io/gh/alielsokary/CaskHub/branch/develop/graph/badge.svg)](https://codecov.io/gh/alielsokary/CaskHub)
[![macOS](https://img.shields.io/badge/macOS-15.6%2B-blue)](https://github.com/alielsokary/CaskHub/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/alielsokary/CaskHub)](https://github.com/alielsokary/CaskHub/releases/latest)

<img width="850" height="250" alt="caskhub-banner-dark" src="https://github.com/user-attachments/assets/24326700-e485-4714-993f-648c2a36c25b" />

**A native macOS app store for Homebrew casks.** Browse, search, install, update, and uninstall thousands of Mac apps distributed through [Homebrew](https://brew.sh) - with original app icons extracted from the source, categories, popularity charts, and one-click actions, all in a clean SwiftUI interface.

CaskHub is 100% free and open source, no subscription, no premium tier, no ads, nothing.

<img width="1492" height="962" alt="caskhub-dark" src="https://github.com/user-attachments/assets/d7899924-6ade-43cc-a3f9-dcabeac9229b" />

## Install

<a href="https://github.com/alielsokary/CaskHub/releases/download/0.8.0/CaskHub-0.8.0.zip"><img src=".github/assets/download-for-macos.png" alt="Download app for macOS" width="194"></a>

Or install with Homebrew:

```bash
brew install --cask caskhub
```

## Features

### Discover

- **Browse** - curated shelves and a rotating hero pick, organized by category
- **Featured** - the top 100 casks ranked by install popularity
- **Top Charts** - most-installed casks with a 30 / 90 / 365-day analytics window
- **Recently Added** - casks newly published to Homebrew in the last 30-90 days
- **Categories** - every cask classified into browsable categories (Developer Tools, Productivity, Design, and more)
- **Search** - instant search (⌘F) across names, tokens, and descriptions

### Manage

- **Install / Update / Uninstall** with live progress states and cancellable downloads
- **Adopt Apps** - bring apps you installed outside Homebrew (a downloaded DMG, another store) under brew management with one click, keeping the app in place
- **Guided Homebrew setup** - walks you through installing Homebrew if it's missing, supports custom installation paths, and picks the native prefix on both Apple Silicon and Intel
- **Smart update detection** - skips self-updating apps and normalizes packaging-suffix version differences, so the Updates badge only shows updates that matter
- **Installed library** - detects what's already in your Caskroom, including apps installed from the command line
- **Native password prompts** - pkg-based casks that need admin rights get a native macOS dialog instead of a terminal prompt
- **Rich metadata** - original app icons, download sizes, install counts, homepages, and version info

### Polish

- Grid and list view modes, flexible sorting, light/dark/system themes
- A custom design system with bundled typography
- Bundled category data ships with the app, so browsing never blocks on the network
- **Built-in app updates** - CaskHub keeps itself up to date via [Sparkle](https://sparkle-project.org)

## How It Works

CaskHub talks to Homebrew on three levels:

1. **Catalog & analytics** come from the public [Homebrew API](https://formulae.brew.sh) (`/api/cask.json` and install analytics). No Homebrew installation is required just to browse.
2. **Installed-app detection** reads install receipts directly from your Caskroom (`$HOMEBREW_PREFIX/Caskroom`) - fast, and no shelling out needed.
3. **Installs, updates, and uninstalls** run through your real `brew` binary, so everything CaskHub does stays fully compatible with the command line. Anything you install in CaskHub can be managed with `brew`, and vice versa.

Categories, first-seen dates, and original app icons are produced by the companion [CaskFlow](https://github.com/alielsokary/CaskFlow) pipeline and consumed via its GitHub Releases. A bundled snapshot ships inside the app, so none of it blocks launch or requires connectivity.

## Requirements

- **macOS 15.6** or later
- **[Homebrew](https://brew.sh)** - required for installing, updating, and uninstalling casks (browsing works without it)

## Building from Source

Prefer building it yourself? You'll need Xcode 26 or later:

```bash
git clone https://github.com/alielsokary/CaskHub.git
cd CaskHub
open CaskHub.xcodeproj
```

Select the **CaskHub** scheme and run (⌘R). Xcode resolves the Swift package dependencies ([Sparkle](https://github.com/sparkle-project/Sparkle), [Sentry](https://github.com/getsentry/sentry-cocoa), and [TelemetryDeck](https://github.com/TelemetryDeck/SwiftSDK)) automatically.

## Architecture

- **SwiftUI + MVVM** with `@Observable` view models and `@MainActor` isolation
- **Protocol-based networking layer** for testability (`BrewAPIClientProtocol`, `NetworkServiceProtocol`) with dependency injection throughout
- **Two-tier icon caching** (memory + disk) and HTTP-header-based download-size resolution
- **Minimal dependencies** - three focused packages: [Sparkle](https://sparkle-project.org) for app updates, [Sentry](https://sentry.io) for crash reporting and usage metrics, and [TelemetryDeck](https://telemetrydeck.com) for session and acquisition analytics

## Testing & CI

Tests run with XCTest on pull requests to `master` and `develop`, and on pushes to `develop`, with coverage reported to Codecov and static analysis by Codacy. A release-freshness check on PRs to `master` ensures the bundled category data is up to date with the latest CaskFlow release.

```bash
xcodebuild test -project CaskHub.xcodeproj -scheme CaskHub -destination 'platform=macOS'
```

## Privacy & Analytics

CaskHub sends anonymous usage metrics through [Sentry](https://sentry.io). [TelemetryDeck](https://telemetrydeck.com) receives only anonymous session and new-install signals used for acquisition and retention reporting.

CaskHub also sends crash reports and technical diagnostics through [Sentry](https://sentry.io) to help diagnose and fix stability issues.

You can opt out of everything at any time in **Settings → Privacy**.

## Localization

CaskHub speaks your language. Currently available in:

- 🇬🇧 **English**
- 🇨🇳 **简体中文 (Simplified Chinese)** — translated by [@carty900-jpg](https://github.com/carty900-jpg)

macOS picks the language automatically from your system preferences; a per-app override is available under **System Settings → General → Language & Region → Applications**.

Want CaskHub in your language? Translations live in a single [String Catalog](CaskHub/Resources/Localizable.xcstrings) — open an issue or PR to add yours.

## Contributing

Interested in contributing to CaskHub? We welcome contributions of all kinds!

- **Code contributions**: Bug fixes, features, improvements
- **Bug reports**: [Found an issue? Let us know](https://github.com/alielsokary/CaskHub/issues/new/choose)
- **Feature requests**: [Have an idea? We'd love to hear it](https://github.com/alielsokary/CaskHub/issues/new/choose)

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request — note that all PRs target the `develop` branch.

## Acknowledgements

- [CaskFlow](https://github.com/alielsokary/CaskFlow) — the data pipeline behind CaskHub's categories, Recently Added dates, and app icons
- [Homebrew](https://brew.sh) — the package manager CaskHub is built on

## License

CaskHub is released under the [MIT License](LICENSE).
