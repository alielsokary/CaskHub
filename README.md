# CaskHub

[![Tests](https://github.com/alielsokary/CaskHub/actions/workflows/tests.yml/badge.svg?branch=develop)](https://github.com/alielsokary/CaskHub/actions/workflows/tests.yml)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/b2d4203ef8724bc0a2265af613ac29c9)](https://app.codacy.com/gh/alielsokary/CaskHub/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![codecov](https://codecov.io/gh/alielsokary/CaskHub/branch/develop/graph/badge.svg)](https://codecov.io/gh/alielsokary/CaskHub)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/alielsokary/CaskHub?include_prereleases)](https://github.com/alielsokary/CaskHub/releases)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015.6%2B-blue)](https://github.com/alielsokary/CaskHub/releases/latest)

<img width="1700" height="500" alt="caskhub-banner-dark" src="https://github.com/user-attachments/assets/24326700-e485-4714-993f-648c2a36c25b" />

**A native macOS app store for Homebrew casks.** Browse, search, install, update, and uninstall thousands of Mac apps distributed through [Homebrew](https://brew.sh) - with original app icons extracted from the source, categories, popularity charts, and one-click actions, all in a clean SwiftUI interface.

CaskHub is 100% free and open source, no subscription, no premium tier, no ads, nothing.

## Install

[![Download CaskHub](https://img.shields.io/badge/Download-Latest%20Release-blue?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/alielsokary/CaskHub/releases/latest)

Or install with Homebrew:

```bash
brew install --cask alielsokary/tap/caskhub
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
- **Smart update detection** - skips self-updating apps and normalizes packaging-suffix version differences, so the Updates badge only shows updates that matter
- **Installed library** - detects what's already in your Caskroom, including apps installed from the command line
- **Native password prompts** - pkg-based casks that need admin rights get a native macOS dialog instead of a terminal prompt
- **Rich metadata** - original app icons, download sizes, install counts, homepages, and version info

### Polish

- Grid and list view modes, flexible sorting, light/dark/system themes
- A custom design system with bundled typography
- Bundled category data ships with the app, so browsing never blocks on the network

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

Select the **CaskHub** scheme and run (⌘R). Xcode resolves the single Swift package dependency ([TelemetryDeck](https://github.com/TelemetryDeck/SwiftSDK)) automatically.

Optional: copy `Configs/Secrets.xcconfig.template` to `Configs/Secrets.xcconfig` and fill in the analytics key — builds work fine without it; analytics just stays off.

## Architecture

- **SwiftUI + MVVM** with `@Observable` view models and `@MainActor` isolation
- **Protocol-based networking layer** for testability (`BrewAPIClientProtocol`, `NetworkServiceProtocol`) with dependency injection throughout
- **Two-tier icon caching** (memory + disk) and HTTP-header-based download-size resolution
- **Zero third-party runtime dependencies** - Foundation, SwiftUI, AppKit, and Observation only

## Testing & CI

Tests run with XCTest on every push and pull request to `master` and `develop`, with coverage reported to Codecov and static analysis by Codacy. A release-freshness check on PRs to `master` ensures the bundled category data is up to date with the latest CaskFlow release.

```bash
xcodebuild test -project CaskHub.xcodeproj -scheme CaskHub -destination 'platform=macOS'
```

## Privacy & Analytics

CaskHub collects anonymous usage analytics through [TelemetryDeck](https://telemetrydeck.com), a privacy-first analytics service. No personal data or identifiers ever leave your Mac — user IDs are salted and hashed on-device, and there is no tracking across apps or websites.

You can opt out at any time in **Settings → Privacy**.

## Contributing

Interested in contributing to CaskHub? We welcome contributions of all kinds!

- **Code contributions**: Bug fixes, features, improvements
- **Bug reports**: Found an issue? Let us know
- **Feature requests**: Have an idea? We'd love to hear it

## License

CaskHub is released under the [MIT License](LICENSE).
