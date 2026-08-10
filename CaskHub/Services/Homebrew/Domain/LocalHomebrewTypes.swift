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

    /// Localized label for display. `rawValue` stays language-independent.
    /// Proper nouns are intentionally left untranslated.
    var title: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .macAppStore: return "Mac App Store"
        case .externalApplication: return String(localized: "External application")
        case .packageInstaller: return String(localized: "Package installer")
        case .externalExecutable: return String(localized: "External executable")
        }
    }
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
        case .opening: return String(localized: "Opening…")
        case .installing: return String(localized: "Installing…")
        case .adopting: return String(localized: "Adopting…")
        case .updating: return String(localized: "Updating…")
        case .uninstalling: return String(localized: "Uninstalling…")
        case .repairing: return String(localized: "Repairing…")
        case .queued: return String(localized: "Queued…")
        }
    }

    /// Stable key for grouping and ordering. Never shown to the user, so it stays
    /// fixed when `inProgressLabel` changes wording.
    var identifier: String {
        switch self {
        case .opening: return "opening"
        case .installing: return "installing"
        case .adopting: return "adopting"
        case .updating: return "updating"
        case .uninstalling: return "uninstalling"
        case .repairing: return "repairing"
        case .queued: return "queued"
        }
    }
}

nonisolated enum CaskActionOrigin: String, Sendable {
    case individual
    case updateAll
    case repair
}
