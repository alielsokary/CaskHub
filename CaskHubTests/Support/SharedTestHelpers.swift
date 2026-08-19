//
//  SharedTestHelpers.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/07/2026.
//

@testable import CaskHub
import Foundation
import XCTest

// MARK: - Mock API

@MainActor
final class MockBrewAPIClient: @MainActor BrewAPIClientProtocol {
    var casks: [Cask] = []
    var casksError: Error?
    var analyticsResponses: [AnalyticsPeriod: CaskAnalyticsResponse] = [:]
    var analyticsError: Error?
    private(set) var analyticsFetches: [AnalyticsPeriod] = []

    @MainActor func fetchAllCasks() async throws -> [Cask] {
        if let casksError { throw casksError }
        return casks
    }

    @MainActor func fetchAnalytics(period: AnalyticsPeriod) async throws -> CaskAnalyticsResponse {
        analyticsFetches.append(period)
        if let analyticsError { throw analyticsError }
        return analyticsResponses[period]
            ?? CaskAnalyticsResponse(items: [])
    }
}

// MARK: - Factories

@MainActor
func makeCask(
    _ token: String,
    name: String? = nil,
    desc: String? = nil,
    version: String = "1.0",
    appNames: [String]? = nil,
    binaryNames: [String]? = nil,
    binarySourcePaths: [String]? = nil,
    packageIdentifiers: [String]? = nil,
    packageAppNames: [String]? = nil,
    applicationBundleIdentifiers: [String]? = nil,
    conflictingCaskTokens: [String] = []
) -> Cask {
    var cask = Cask.preview(
        token: token,
        name: name,
        desc: desc,
        version: version,
        conflictingCaskTokens: conflictingCaskTokens
    )
    var artifacts: [ArtifactStanza] = []
    if let appNames {
        artifacts.append(ArtifactStanza(
            keys: ["app"],
            appNames: appNames,
            adoptionSourcePaths: []
        ))
    }
    if binaryNames != nil || binarySourcePaths != nil {
        artifacts.append(ArtifactStanza(
            keys: ["binary"],
            binaryNames: binaryNames ?? [],
            binarySourcePaths: binarySourcePaths ?? [],
            adoptionSourcePaths: binarySourcePaths ?? []
        ))
    }
    if packageIdentifiers != nil || packageAppNames != nil
        || applicationBundleIdentifiers != nil {
        artifacts.append(ArtifactStanza(
            keys: ["pkg", "uninstall"],
            adoptionSourcePaths: [],
            packageIdentifiers: packageIdentifiers ?? [],
            deletedAppNames: packageAppNames ?? [],
            applicationBundleIdentifiers: applicationBundleIdentifiers ?? []
        ))
    }
    cask.artifacts = artifacts.isEmpty ? nil : artifacts
    return cask
}

@MainActor
func analyticsResponse(_ counts: [(String, String)]) -> CaskAnalyticsResponse {
    CaskAnalyticsResponse(
        items: counts.map {
            CaskAnalyticsItem(cask: $0.0, count: $0.1)
        }
    )
}

@MainActor
func installation(_ token: String, version: String) -> LocalCaskInstallation {
    LocalCaskInstallation(token: token, installedVersion: version, installedAt: nil, appBundleNames: [])
}

@MainActor
struct InstallationSnapshotFixture {
    var installedCasks: [String: LocalCaskInstallation]
    var externalAppNames: Set<String>
    var externalApplicationOwners: [String: DetectedApplication]
    var externalPackageApplicationOwners: [String: DetectedApplication]
    var macAppStoreAppNames: Set<String>
    var macAppStoreBundleIdentifiers: [String: Set<String>]
    var detectedApplications: [DetectedApplication]
    var externalBinaryPaths: [String: URL]
    var externalPackageInstallations: [String: ExternalPackageInstallation]
    var installationIndex: CaskInstallationIndex
    var installationDatesByToken: [String: CaskInstallationDates]
    var scannedAt: Date?

    init(snapshot: InstallationSnapshot) {
        installedCasks = snapshot.installedCasks
        externalAppNames = snapshot.externalAppNames
        externalApplicationOwners = snapshot.externalApplicationOwners
        externalPackageApplicationOwners = snapshot.externalPackageApplicationOwners
        macAppStoreAppNames = snapshot.macAppStoreAppNames
        macAppStoreBundleIdentifiers = snapshot.macAppStoreBundleIdentifiers
        detectedApplications = snapshot.detectedApplications
        externalBinaryPaths = snapshot.externalBinaryPaths
        externalPackageInstallations = snapshot.externalPackageInstallations
        installationIndex = snapshot.installationIndex
        installationDatesByToken = snapshot.installationDatesByToken
        scannedAt = snapshot.scannedAt
    }

    func makeSnapshot() -> InstallationSnapshot {
        InstallationSnapshot(
            installedCasks: installedCasks,
            applications: ApplicationInstallationSnapshot(
                externalAppNames: externalAppNames,
                externalApplicationOwners: externalApplicationOwners,
                externalPackageApplicationOwners: externalPackageApplicationOwners,
                macAppStoreAppNames: macAppStoreAppNames,
                macAppStoreBundleIdentifiers: macAppStoreBundleIdentifiers,
                detectedApplications: detectedApplications
            ),
            externalBinaryPaths: externalBinaryPaths,
            externalPackageInstallations: externalPackageInstallations,
            installationIndex: installationIndex,
            installationDatesByToken: installationDatesByToken,
            scannedAt: scannedAt
        )
    }
}

@MainActor
func updateInstallationSnapshot(
    of service: LocalHomebrewService,
    update: (inout InstallationSnapshotFixture) -> Void
) {
    var fixture = InstallationSnapshotFixture(
        snapshot: service.installationSnapshot
    )
    update(&fixture)
    service.commitInstallationSnapshot(fixture.makeSnapshot())
}

@MainActor
func updateInstalledCask(
    _ installation: LocalCaskInstallation,
    in service: LocalHomebrewService
) {
    var installedCasks = service.installationSnapshot.installedCasks
    installedCasks[installation.token] = installation
    updateInstallationSnapshot(of: service) {
        $0.installedCasks = installedCasks
        $0.installationDatesByToken[installation.token] = CaskInstallationDates(
            installedAt: installation.installedAt,
            lastUpdatedAt: installation.lastUpdatedAt,
            basis: .homebrewMetadata
        )
    }
}

func dateString(daysAgo: Int) -> String {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
    return date.formatted(.iso8601.year().month().day())
}

@discardableResult
func makeApplicationBundle(
    in directory: URL,
    named name: String,
    bundleIdentifier: String,
    macAppStoreReceipt: Bool = false
) throws -> URL {
    let fileManager = FileManager.default
    let appURL = directory.appendingPathComponent(name)
    let executableName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    let contentsURL = appURL.appendingPathComponent("Contents")
    let executableURL = contentsURL.appendingPathComponent("MacOS/\(executableName)")
    try fileManager.createDirectory(
        at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let info: [String: Any] = [
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleExecutable": executableName,
        "CFBundleName": executableName,
        "CFBundlePackageType": "APPL"
    ]
    let infoData = try PropertyListSerialization.data(
        fromPropertyList: info, format: .xml, options: 0
    )
    try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    if macAppStoreReceipt {
        let receiptURL = contentsURL.appendingPathComponent("_MASReceipt/receipt")
        try fileManager.createDirectory(
            at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: receiptURL)
    }
    return appURL
}

func setApplicationVersion(_ version: String, at appURL: URL) throws {
    let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
    let data = try Data(contentsOf: plistURL)
    var info = try XCTUnwrap(
        PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any]
    )
    info["CFBundleShortVersionString"] = version
    let updated = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    try updated.write(to: plistURL)
}

@MainActor
func makeViewModel(
    api: MockBrewAPIClient,
    categories: CategoryService? = nil,
    recentlyAdded: RecentlyAddedService? = nil,
    localHomebrew: LocalHomebrewService? = nil,
    defaults: UserDefaults? = nil
) -> CaskCatalogViewModel {
    let vm = CaskCatalogViewModel(
        apiClient: api,
        categoryService: categories ?? CategoryService(),
        recentlyAdded: recentlyAdded ?? RecentlyAddedService(),
        localHomebrew: localHomebrew ?? LocalHomebrewService(),
        defaults: defaults ?? makeScratchDefaults("viewmodel-scratch")
    )
    vm.searchDebounceInterval = .zero
    return vm
}

func makeScratchDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "test.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
func makeSUT(
    casks: [Cask] = [],
    analytics: [(String, String)]? = nil,
    categories: CategoryService? = nil,
    recentlyAdded: RecentlyAddedService? = nil,
    localHomebrew: LocalHomebrewService? = nil
) async -> (vm: CaskCatalogViewModel, api: MockBrewAPIClient) {
    let api = MockBrewAPIClient()
    api.casks = casks
    if let analytics {
        api.analyticsResponses[.days365] = analyticsResponse(analytics)
    }
    let vm = makeViewModel(
        api: api,
        categories: categories,
        recentlyAdded: recentlyAdded,
        localHomebrew: localHomebrew
    )
    await vm.fetchCasks()
    return (vm, api)
}

@MainActor
func seededCategories(_ tokenToCategory: [String: TokenCategoryMapping],
                      categories: [String: CategoryDefinition]) -> CategoryService {
    let service = CategoryService()
    service.applyData(CaskCategoryData(
        version: 1,
        generatedDate: "2026-07-11",
        releaseTag: nil,
        categories: categories,
        tokenToCategory: tokenToCategory,
        iconTokens: nil
    ))
    return service
}

@MainActor
final class RecordingApplicationLauncher: ApplicationLaunching {
    private(set) var openedURLs: [URL] = []

    var lastOpenedURL: URL? {
        openedURLs.last
    }

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}

nonisolated final class RecordingMaintenanceProbe: MaintenanceProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResults: [String: BrewProbeResult] = [:]
    private var storedDefault: BrewProbeResult? = BrewProbeResult(exitCode: 0, output: "")
    private var storedSizes: [String: Int64] = [:]
    private var storedRemoveSucceeds = true
    private var storedCommands: [[String]] = []
    private var storedEnvironments: [[String: String]?] = []
    private var storedRemoved: [URL] = []
    private var storedInstallers: [CachedInstaller] = []

    var resultsByFirstArgument: [String: BrewProbeResult] {
        get { lock.withLock { storedResults } }
        set { lock.withLock { storedResults = newValue } }
    }

    var directorySizes: [String: Int64] {
        get { lock.withLock { storedSizes } }
        set { lock.withLock { storedSizes = newValue } }
    }

    var removeSucceeds: Bool {
        get { lock.withLock { storedRemoveSucceeds } }
        set { lock.withLock { storedRemoveSucceeds = newValue } }
    }

    var cachedInstallersResult: [CachedInstaller] {
        get { lock.withLock { storedInstallers } }
        set { lock.withLock { storedInstallers = newValue } }
    }

    var commands: [[String]] { lock.withLock { storedCommands } }
    var environments: [[String: String]?] { lock.withLock { storedEnvironments } }
    var removedDirectories: [URL] { lock.withLock { storedRemoved } }

    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) async -> BrewProbeResult? {
        lock.withLock {
            storedCommands.append([executable.lastPathComponent] + arguments)
            storedEnvironments.append(environment)
            if let first = arguments.first, let result = storedResults[first] {
                return result
            }
            return storedDefault
        }
    }

    func directorySize(at url: URL) async -> Int64 {
        lock.withLock { storedSizes[url.lastPathComponent] ?? 0 }
    }

    func removeDirectoryContents(at url: URL) async -> Bool {
        lock.withLock {
            storedRemoved.append(url)
            return storedRemoveSucceeds
        }
    }

    func cachedInstallers(at cacheURL: URL) async -> [CachedInstaller] {
        lock.withLock { storedInstallers }
    }
}

nonisolated struct EmptyInstalledSoftwareScanner: InstalledSoftwareScanning {
    func scan(_ request: InstalledSoftwareScanRequest) async -> InstallationSnapshot {
        .empty
    }

    func reconcileCatalog(
        _ request: InstalledSoftwareScanRequest,
        with current: InstallationSnapshot
    ) async -> InstallationSnapshot {
        current
    }
}

@MainActor
final class RecordingHomebrewCommandExecutor: HomebrewCommandExecuting {
    private(set) var requests: [HomebrewCommandRequest] = []

    func execute(
        _ request: HomebrewCommandRequest,
        onStart: @escaping @MainActor @Sendable () -> Void,
        onChunk _: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        requests.append(request)
        onStart()
        return BrewProcessResult(exitCode: 0, output: "")
    }

    func cancel(token _: String) -> Bool { false }
}

// MARK: - Crash-reporting spies

final class SpyCrashSpan: CrashSpan {
    var finished = false
    var finishedError: Error?
    func finish() {
        finished = true
    }

    func finish(error: Error) {
        finished = true
        finishedError = error
    }
}

final class SpyCrashReporterProvider: CrashReporterProvider {
    struct SpanRecord {
        let name: String
        let operation: String
        let span: SpyCrashSpan
    }

    var startedWith: [SentryConsent] = []
    var consentChanges: [SentryConsent] = []
    var capturedErrors: [Error] = []
    var breadcrumbs: [(message: String, data: [String: String])] = []
    var tags: [String: String] = [:]
    var spans: [SpanRecord] = []
    var hangTrackingEvents: [String] = []

    func pauseHangTracking() {
        hangTrackingEvents.append("pause")
    }

    func resumeHangTracking() {
        hangTrackingEvents.append("resume")
    }

    func start(consent: SentryConsent) {
        startedWith.append(consent)
    }

    func setConsent(_ consent: SentryConsent) {
        consentChanges.append(consent)
    }

    func capture(_ error: Error) {
        capturedErrors.append(error)
    }

    func setTag(_ key: String, value: String) {
        tags[key] = value
    }

    func addBreadcrumb(_ message: String, data: [String: String]) {
        breadcrumbs.append((message, data))
    }

    func startSpan(name: String, operation: String) -> CrashSpan {
        let span = SpyCrashSpan()
        spans.append(SpanRecord(name: name, operation: operation, span: span))
        return span
    }
}
