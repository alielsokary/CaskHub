# Security Policy

CaskHub is a free, open-source macOS app. This policy explains how to report security issues, what to expect, and what is in scope.

## Supported Versions

CaskHub follows a rolling release model. Security fixes ship in a new release rather than being backported.

| Version                                                                  | Supported |
| ------------------------------------------------------------------------ | --------- |
| [Latest release](https://github.com/alielsokary/CaskHub/releases/latest) | ✅        |
| Older releases                                                            | ❌        |

If you are on an older version, update via the in-app updater or `brew upgrade --cask caskhub` before reporting.

## Reporting a Vulnerability

You **must not** report security vulnerabilities through public GitHub issues, discussions, or pull requests.

Instead, report them privately through GitHub's private vulnerability reporting:

**[Open a security advisory](https://github.com/alielsokary/CaskHub/security/advisories/new)**

If you cannot use the advisory form, open a regular [issue](https://github.com/alielsokary/CaskHub/issues) asking for a private contact channel, without including vulnerability details.

Reports **should** include:

- A description of the vulnerability and its impact
- Step-by-step instructions to reproduce the issue
- The CaskHub and macOS versions you tested
- Proof-of-concept code, screenshots, and a suggested mitigation, if you have them

### What to expect

CaskHub is maintained by a single developer in their spare time, so please allow a little slack on timelines:

- Your report will be acknowledged within 7 days.
- You will receive updates as the issue is triaged and fixed.
- Confirmed vulnerabilities are fixed as quickly as severity demands, and the fix ships in a new release.

### Disclosure policy

We follow coordinated disclosure. You **should** allow up to 90 days for a fix to be released before disclosing the issue publicly.

Once fixed, an advisory will be published. You will be credited for the discovery unless you prefer to remain anonymous.

There is no bug bounty program, since CaskHub is free software with no revenue, but reporters are credited in the advisory and release notes.

## Scope

### In scope (report privately)

- The CaskHub app itself: all code in this repository
- The release and update pipeline: GitHub Releases artifacts, the [Homebrew tap](https://github.com/alielsokary/homebrew-tap) cask, and the Sparkle appcast (releases are Developer ID-signed and notarized; updates are EdDSA-verified)
- The [caskhub.app](https://caskhub.app) website content

Examples of in-scope issues:

- Executing attacker-controlled code through CaskHub, e.g. command injection via cask metadata into the `brew` commands CaskHub runs
- Bypassing or downgrading Sparkle update signature verification
- Tampering with CaskHub's release artifacts, appcast, or tap through the project's CI
- CaskHub leaking sensitive user data

### Out of scope (report elsewhere or publicly)

- **Homebrew itself.** CaskHub is a graphical interface over `brew`. Vulnerabilities in Homebrew belong to [Homebrew's security policy](https://github.com/Homebrew/brew/security/policy).
- **Malicious or vulnerable casks.** CaskHub displays Homebrew's cask catalog and delegates installs to `brew`. Report problematic third-party apps to [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) or the app's developer.
- **Attacks requiring local control.** CaskHub runs `brew` as the local user. Reports that require the attacker to already control the user's account, shell environment, Homebrew prefix, or machine are not CaskHub vulnerabilities.
- **Third-party dependencies** without a demonstrated impact on CaskHub. Report those upstream; we will still bump the dependency.
- **Crashes, hangs, or resource exhaustion** with no security impact. File these as regular [bug reports](https://github.com/alielsokary/CaskHub/issues).
- **Availability of third-party services** CaskHub relies on (GitHub, Homebrew's API, formulae.brew.sh).

Thank you for helping keep CaskHub and its users safe!
