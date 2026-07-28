# Security Policy

CaskHub is a free, open-source macOS app. We take the security of the app and its release pipeline seriously, and we appreciate the work of security researchers who report issues responsibly.

## Supported Versions

CaskHub follows a rolling release model. Security fixes ship in a new release rather than being backported.

| Version                                                                  | Supported |
| ------------------------------------------------------------------------ | --------- |
| [Latest release](https://github.com/alielsokary/CaskHub/releases/latest) | ✅        |
| Older releases                                                            | ❌        |

If you are on an older version, update via the in-app updater or `brew upgrade --cask caskhub` before reporting.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

Report them privately through GitHub's private vulnerability reporting:

**[Open a security advisory](https://github.com/alielsokary/CaskHub/security/advisories/new)**

Please include as much of the following as you can:

- A description of the vulnerability and its impact
- Step-by-step instructions to reproduce the issue
- The CaskHub version and macOS version you tested
- Any proof-of-concept code or screenshots
- A suggested mitigation, if you have one

### What to expect

CaskHub is maintained by a single developer in their spare time, so please allow a little slack on timelines:

- Your report will be acknowledged within **7 days**.
- You will receive updates as the issue is triaged and fixed.
- Confirmed vulnerabilities will be fixed as quickly as severity demands, and the fix will ship in a new release.

### Disclosure policy

We follow coordinated disclosure. Please allow a reasonable amount of time (up to 90 days) for a fix to be released before disclosing the issue publicly. Once fixed, an advisory will be published and you will be credited for the discovery unless you prefer to remain anonymous.

There is no bug bounty program — CaskHub is free software with no revenue — but reporters are credited in the advisory and release notes.

## Scope

### In scope

- The CaskHub app itself (all code in this repository)
- The release and update pipeline:
  - GitHub Releases artifacts and the [Homebrew tap](https://github.com/alielsokary/homebrew-tap) cask
  - The Sparkle appcast and update verification (releases are Developer ID–signed and notarized; updates are EdDSA-verified)
- The [caskhub.app](https://caskhub.app) website content

Examples of in-scope issues:

- Executing attacker-controlled code through CaskHub (e.g. command injection via cask metadata into the `brew` commands CaskHub runs)
- Bypassing or downgrading Sparkle update signature verification
- Tampering with CaskHub's release artifacts, appcast, or tap through the project's CI
- CaskHub leaking sensitive user data

### Out of scope

- **Homebrew itself.** CaskHub is a GUI over `brew`; vulnerabilities in Homebrew belong to [Homebrew's security policy](https://github.com/Homebrew/brew/security/policy).
- **Malicious or vulnerable casks.** CaskHub displays Homebrew's cask catalog and delegates installs to `brew`. Problematic third-party apps should be reported to [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) or the app's developer. Installing an app remains a trust decision the user makes about that app.
- **Attacks requiring local control.** CaskHub runs `brew` as the local user. Reports that require the attacker to already control the user's account, shell environment, Homebrew prefix, or machine are not CaskHub vulnerabilities.
- **Third-party dependencies** without a demonstrated impact on CaskHub — report those upstream (we will still bump the dependency).
- **Crashes, hangs, or resource exhaustion** with no security impact — please file these as regular [bug reports](https://github.com/alielsokary/CaskHub/issues).
- **Availability of third-party services** CaskHub relies on (GitHub, Homebrew's API, formulae.brew.sh).

Thank you for helping keep CaskHub and its users safe!
