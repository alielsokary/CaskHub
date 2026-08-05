//
//  LocalHomebrewTypes.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

nonisolated struct ApplicationBundleMetadata {
    let bundleIdentifier: String?
}

nonisolated struct DetectedApplication: Hashable, Sendable {
    let url: URL
    let bundleName: String
    let bundleIdentifier: String?
    let isMacAppStore: Bool
    let isDirectlyInApplicationDirectory: Bool
    let installedAt: Date?
    let lastUpdatedAt: Date?

    init(
        url: URL,
        bundleName: String,
        bundleIdentifier: String?,
        isMacAppStore: Bool,
        isDirectlyInApplicationDirectory: Bool,
        installedAt: Date? = nil,
        lastUpdatedAt: Date? = nil
    ) {
        self.url = url
        self.bundleName = bundleName
        self.bundleIdentifier = bundleIdentifier
        self.isMacAppStore = isMacAppStore
        self.isDirectlyInApplicationDirectory = isDirectlyInApplicationDirectory
        self.installedAt = installedAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}

nonisolated struct ExternalApplicationScan: Sendable {
    let applications: [DetectedApplication]

    var adoptableNames: Set<String> {
        Set(applications.lazy.filter {
            !$0.isMacAppStore && $0.isDirectlyInApplicationDirectory
        }.map(\.bundleName))
    }

    var nonStoreNames: Set<String> {
        Set(applications.lazy.filter { !$0.isMacAppStore }.map(\.bundleName))
    }

    var macAppStoreNames: Set<String> {
        Set(applications.lazy.filter(\.isMacAppStore).map(\.bundleName))
    }

    var macAppStoreBundleIdentifiers: [String: Set<String>] {
        applications.lazy.filter(\.isMacAppStore).reduce(into: [:]) { result, application in
            guard let bundleIdentifier = application.bundleIdentifier else { return }
            result[application.bundleName, default: []].insert(bundleIdentifier)
        }
    }
}

nonisolated struct ApplicationCaskSignature: Sendable {
    let token: String
    let appBundleNames: Set<String>
    let bundleIdentifiers: Set<String>
}

nonisolated struct MacAppStoreCaskSignature: Sendable {
    let token: String
    let bundleNames: Set<String>
    let hasPackageArtifact: Bool
    let applicationBundleIdentifiers: [String]
    let packageIdentifiers: [String]
}

nonisolated struct BinaryCaskSignature: Sendable {
    let token: String
    let binaryNames: [String]
}

nonisolated struct CaskApplicationSignature: Sendable {
    let token: String
    let currentBundleNames: Set<String>
    let launchableBundleNames: Set<String>
}

nonisolated struct CaskInstallationCatalog: Sendable {
    let tokens: Set<String>
    let macAppStoreSignatures: [MacAppStoreCaskSignature]
    let binarySignatures: [BinaryCaskSignature]
    let applicationSignatures: [CaskApplicationSignature]

    init(
        tokens: Set<String>,
        macAppStoreSignatures: [MacAppStoreCaskSignature],
        binarySignatures: [BinaryCaskSignature],
        applicationSignatures: [CaskApplicationSignature] = []
    ) {
        self.tokens = tokens
        self.macAppStoreSignatures = macAppStoreSignatures
        self.binarySignatures = binarySignatures
        self.applicationSignatures = applicationSignatures
    }

    static let empty = CaskInstallationCatalog(
        tokens: [], macAppStoreSignatures: [], binarySignatures: []
    )
}

nonisolated struct CaskInstallationIndex: Sendable {
    let catalogTokens: Set<String>
    let macAppStoreApplications: [String: DetectedApplication]
    let externalCLIPaths: [String: URL]
    let launchableHomebrewTokens: Set<String>
    let verifiedZombieTokens: Set<String>

    init(
        catalogTokens: Set<String>,
        macAppStoreApplications: [String: DetectedApplication],
        externalCLIPaths: [String: URL],
        launchableHomebrewTokens: Set<String> = [],
        verifiedZombieTokens: Set<String> = []
    ) {
        self.catalogTokens = catalogTokens
        self.macAppStoreApplications = macAppStoreApplications
        self.externalCLIPaths = externalCLIPaths
        self.launchableHomebrewTokens = launchableHomebrewTokens
        self.verifiedZombieTokens = verifiedZombieTokens
    }

    static let empty = CaskInstallationIndex(
        catalogTokens: [], macAppStoreApplications: [:], externalCLIPaths: [:]
    )
}

nonisolated struct PackageCaskSignature: Sendable {
    let token: String
    let displayName: String
    let receiptPatterns: [String]
    let appNameCandidates: [String]
}

nonisolated struct PackageInstallationCandidate {
    let signature: PackageCaskSignature
    let appBundleNames: Set<String>
    let score: Int
    let isHomebrewInstalled: Bool
}

nonisolated struct ExternalPackageInstallation: Hashable, Sendable {
    let appBundleNames: [String]
}

nonisolated enum CaskInstallationSource: String, Equatable, Sendable {
    case homebrew = "Homebrew"
    case macAppStore = "Mac App Store"
    case externalApplication = "External application"
    case packageInstaller = "Package installer"
    case externalExecutable = "External executable"
}

nonisolated enum CaskUninstallAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case notApplicable

    var unavailableReason: String? {
        guard case let .unavailable(reason) = self else { return nil }
        return reason
    }
}

nonisolated struct CaskLocalState: Equatable, Sendable {
    let installationSource: CaskInstallationSource?
    let externalCLIPath: URL?
    let uninstallAvailability: CaskUninstallAvailability
    let hasAvailableUpdate: Bool
    let isZombie: Bool
    let canOpen: Bool

    var isPresent: Bool {
        installationSource != nil
    }

    var isHomebrewInstalled: Bool {
        installationSource == .homebrew
    }

    var isAdoptable: Bool {
        installationSource == .externalApplication
            || installationSource == .packageInstaller
    }

    var isExternalPackage: Bool {
        installationSource == .packageInstaller
    }
}

nonisolated struct LocalCaskInstallation: Hashable, Identifiable, Sendable {
    let token: String
    let installedVersion: String
    let installedAt: Date?
    let lastUpdatedAt: Date?
    let appBundleNames: [String]

    /// Brew still lists this cask, but its app was removed outside Homebrew
    /// (or its install receipt is gone) — opens and upgrades are doomed.
    let isZombie: Bool

    nonisolated init(
        token: String,
        installedVersion: String,
        installedAt: Date?,
        lastUpdatedAt: Date? = nil,
        appBundleNames: [String],
        isZombie: Bool = false
    ) {
        self.token = token
        self.installedVersion = installedVersion
        self.installedAt = installedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.appBundleNames = appBundleNames
        self.isZombie = isZombie
    }

    var id: String {
        token
    }
}

nonisolated enum CaskInstallationDateBasis: Equatable, Sendable {
    case homebrewMetadata
    case applicationBundleAttributes
}

nonisolated struct CaskInstallationDates: Equatable, Sendable {
    let installedAt: Date?
    let lastUpdatedAt: Date?
    let basis: CaskInstallationDateBasis

    init(
        installedAt: Date?,
        lastUpdatedAt: Date?,
        basis: CaskInstallationDateBasis = .homebrewMetadata
    ) {
        self.installedAt = installedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.basis = basis
    }
}

nonisolated enum CaskAction: Equatable, Sendable {
    case opening
    case installing
    case adopting
    case updating
    case uninstalling
    case repairing
    case queued

    var inProgressLabel: String {
        switch self {
        case .opening: return "Opening…"
        case .installing: return "Installing…"
        case .adopting: return "Adopting…"
        case .updating: return "Updating…"
        case .uninstalling: return "Uninstalling…"
        case .repairing: return "Repairing…"
        case .queued: return "Queued…"
        }
    }
}

nonisolated enum CaskActionOrigin: String, Sendable {
    case individual
    case updateAll
    case repair
}

enum LocalHomebrewError: LocalizedError {
    case brewBinaryNotFound
    case appBundleNotFound(token: String)
    case brewCommandFailed(args: [String], exitCode: Int32, stderr: String)

    /// Failures with a complete in-app recovery path are user state, not defects.
    var shouldReport: Bool {
        switch self {
        case .brewBinaryNotFound:
            return false
        case .appBundleNotFound:
            return true
        case let .brewCommandFailed(_, _, stderr):
            return !Self.recoverableFailureClasses.contains(Self.failureClass(stderr: stderr))
        }
    }

    /// Coarse classes for Sentry grouping — one issue per way brew fails, not per cask.
    static func failureClass(stderr: String) -> String {
        if isStrandedApp(stderr: stderr) { return "stranded-caskroom-app" }
        if isAppManagementDenial(stderr: stderr) { return "permission-denied" }
        return failurePatterns.first { stderr.contains($0.fragment) }?.classification
            ?? "uncategorized"
    }

    private static let failurePatterns: [(fragment: String, classification: String)] = [
        // First: a declined askpass prompt is the terminal cause even when the
        // stderr also carries fragments of later patterns (e.g. brew's
        // incidental "already a Binary at" warnings).
        ("sudo: no password was provided", "sudo-declined"),
        ("sudo: a password is required", "sudo-declined"),
        ("is not there", "missing-artifact-source"),
        ("different from the one being installed", "adopt-version-mismatch"),
        ("No Cask with this name exists", "unknown-cask"),
        ("No casks found", "unknown-cask"),
        ("is not installed", "not-installed"),
        ("reports different checksum", "checksum-mismatch"),
        ("SHA256 mismatch", "checksum-mismatch"),
        ("curl: (5)", "network-failure"),
        ("curl: (6)", "network-failure"),
        ("curl: (7)", "network-failure"),
        ("curl: (28)", "network-failure"),
        ("already a Binary at", "binary-conflict"),
        ("already an App at", "app-conflict")
    ]

    private static let recoverableFailureClasses: Set<String> = [
        "adopt-version-mismatch",
        "checksum-mismatch",
        "network-failure",
        "permission-denied",
        "stranded-caskroom-app",
        "sudo-declined"
    ]

    /// A previous interrupted operation parked the real .app inside the Caskroom
    /// version directory; every upgrade then fails until the copy is cleared.
    static func isStrandedApp(stderr: String) -> Bool {
        stderr.contains("already an App at") && stderr.contains("Caskroom")
    }

    var errorDescription: String? {
        switch self {
        case .brewBinaryNotFound:
            return "Couldn't locate the brew binary. Is Homebrew installed?"
        case let .appBundleNotFound(token):
            return "Couldn't find an installed app for \(token)."
        case let .brewCommandFailed(args, code, stderr):
            let cmd = (["brew"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isAppManagementDenial(stderr: trimmed) {
                return "macOS blocked CaskHub from modifying apps on your Mac. "
                    + "Enable CaskHub under System Settings → Privacy & Security → "
                    + "App Management, then try again."
            }
            if Self.isStrandedApp(stderr: trimmed) {
                return "A previous update left an old copy of the app inside Homebrew's "
                    + "records, and Homebrew refuses every upgrade until it's cleared. "
                    + "Repair removes the leftover copy and reinstalls the app fresh — "
                    + "your settings and data are kept."
            }
            if Self.isAdoptMismatch(args: args, stderr: trimmed) {
                return "Your installed copy doesn't match the version Homebrew has on record, "
                    + "so it can't be adopted as-is. You can replace it with Homebrew's copy "
                    + "instead — your settings and data are kept."
            }
            if Self.failureClass(stderr: trimmed) == "sudo-declined" {
                return "This step needs your administrator password. "
                    + "Try again and enter your password when CaskHub asks for it."
            }
            if trimmed.contains("reports different checksum") || trimmed.contains("SHA256 mismatch") {
                return "The download doesn't match the checksum Homebrew has on record — "
                    + "the developer likely replaced the release file after it was published. "
                    + "This isn't a problem with your Mac; Homebrew refuses mismatched downloads "
                    + "for security. Try again in a day or two once the cask is updated."
            }
            return trimmed.isEmpty
                ? "`\(cmd)` failed (exit \(code))."
                : "`\(cmd)` failed (exit \(code)): \(trimmed)"
        }
    }

    /// The App Management (TCC) permission gating modification of other apps' bundles.
    static func isAppManagementDenial(stderr: String) -> Bool {
        stderr.components(separatedBy: .newlines).contains { line in
            line.contains("Operation not permitted")
                && line.contains("/Applications/")
                && line.contains(".app")
        }
    }

    /// `brew install --adopt` refuses when the on-disk app differs from the cask's version.
    static func isAdoptMismatch(args: [String], stderr: String) -> Bool {
        args.contains("--adopt")
            && (stderr.contains("different from the one being installed")
                || stderr.contains("already an App at"))
    }
}
