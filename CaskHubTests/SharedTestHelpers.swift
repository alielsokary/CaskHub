//
//  SharedTestHelpers.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/07/2026.
//

@testable import CaskHub
import Foundation

// MARK: - Mock API

@MainActor
final class MockBrewAPIClient: BrewAPIClientProtocol {
    var casks: [Cask] = []
    var casksError: Error?
    var analyticsResponses: [AnalyticsPeriod: CaskAnalyticsResponse] = [:]
    var analyticsError: Error?
    private(set) var analyticsFetches: [AnalyticsPeriod] = []

    func fetchAllCasks() async throws -> [Cask] {
        if let casksError { throw casksError }
        return casks
    }

    func fetchAnalytics(period: AnalyticsPeriod) async throws -> CaskAnalyticsResponse {
        analyticsFetches.append(period)
        if let analyticsError { throw analyticsError }
        return analyticsResponses[period]
            ?? CaskAnalyticsResponse(category: "", totalItems: 0, startDate: "", endDate: "", totalCount: 0, items: [])
    }
}

// MARK: - Factories

struct TestCaskLifecycle {
    let deprecated: Bool
    let disabled: Bool
    let autoUpdates: Bool?

    static let current = Self(deprecated: false, disabled: false, autoUpdates: nil)
    static let deprecated = Self(deprecated: true, disabled: false, autoUpdates: nil)
    static let disabled = Self(deprecated: false, disabled: true, autoUpdates: nil)
    static let autoUpdating = Self(deprecated: false, disabled: false, autoUpdates: true)
}

@MainActor
func makeCask(
    _ token: String,
    name: String? = nil,
    desc: String? = nil,
    version: String = "1.0",
    lifecycle: TestCaskLifecycle = .current,
    appNames: [String]? = nil,
    binaryNames: [String]? = nil,
    binarySourcePaths: [String]? = nil,
    packageIdentifiers: [String]? = nil,
    packageAppNames: [String]? = nil,
    applicationBundleIdentifiers: [String]? = nil
) -> Cask {
    var cask = Cask.preview(
        token: token,
        name: name,
        desc: desc,
        version: version,
        deprecated: lifecycle.deprecated,
        disabled: lifecycle.disabled,
        autoUpdates: lifecycle.autoUpdates
    )
    var artifacts: [ArtifactStanza] = []
    if let appNames { artifacts.append(ArtifactStanza(keys: ["app"], appNames: appNames)) }
    if binaryNames != nil || binarySourcePaths != nil {
        artifacts.append(ArtifactStanza(
            keys: ["binary"],
            binaryNames: binaryNames ?? [],
            binarySourcePaths: binarySourcePaths ?? []
        ))
    }
    if packageIdentifiers != nil || packageAppNames != nil
        || applicationBundleIdentifiers != nil {
        artifacts.append(ArtifactStanza(
            keys: ["pkg", "uninstall"],
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
        category: "cask_install",
        totalItems: counts.count,
        startDate: "",
        endDate: "",
        totalCount: 0,
        items: counts.enumerated().map {
            CaskAnalyticsItem(number: $0.offset + 1, cask: $0.element.0, count: $0.element.1, percent: "0")
        }
    )
}

@MainActor
func installation(_ token: String, version: String) -> LocalCaskInstallation {
    LocalCaskInstallation(token: token, installedVersion: version, installedAt: nil, appBundleNames: [])
}

@MainActor
func updateInstallationSnapshot(
    of service: LocalHomebrewService,
    installedCasks: [String: LocalCaskInstallation]? = nil,
    externalAppNames: Set<String>? = nil,
    externalApplicationOwners: [String: DetectedApplication]? = nil,
    macAppStoreAppNames: Set<String>? = nil,
    macAppStoreBundleIdentifiers: [String: Set<String>]? = nil,
    detectedApplications: [DetectedApplication]? = nil,
    externalBinaryPaths: [String: URL]? = nil,
    externalPackageInstallations: [String: ExternalPackageInstallation]? = nil,
    installationIndex: CaskInstallationIndex? = nil
) {
    let current = service.installationSnapshot
    service.commitInstallationSnapshot(InstallationSnapshot(
        installedCasks: installedCasks ?? current.installedCasks,
        externalAppNames: externalAppNames ?? current.externalAppNames,
        externalApplicationOwners:
            externalApplicationOwners ?? current.externalApplicationOwners,
        macAppStoreAppNames: macAppStoreAppNames ?? current.macAppStoreAppNames,
        macAppStoreBundleIdentifiers:
            macAppStoreBundleIdentifiers ?? current.macAppStoreBundleIdentifiers,
        detectedApplications: detectedApplications ?? current.detectedApplications,
        externalBinaryPaths: externalBinaryPaths ?? current.externalBinaryPaths,
        externalPackageInstallations:
            externalPackageInstallations ?? current.externalPackageInstallations,
        installationIndex: installationIndex ?? current.installationIndex,
        scannedAt: current.scannedAt
    ))
}

@MainActor
func updateInstalledCask(
    _ installation: LocalCaskInstallation,
    in service: LocalHomebrewService
) {
    var installedCasks = service.installationSnapshot.installedCasks
    installedCasks[installation.token] = installation
    updateInstallationSnapshot(of: service, installedCasks: installedCasks)
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

@MainActor
func makeViewModel(
    api: MockBrewAPIClient,
    categories: CategoryService? = nil,
    recentlyAdded: RecentlyAddedService? = nil,
    localHomebrew: LocalHomebrewService? = nil,
    defaults: UserDefaults? = nil
) -> CaskCatalogViewModel {
    CaskCatalogViewModel(
        apiClient: api,
        categoryService: categories ?? CategoryService(),
        recentlyAdded: recentlyAdded ?? RecentlyAddedService(),
        localHomebrew: localHomebrew ?? LocalHomebrewService(),
        defaults: defaults ?? makeScratchDefaults("viewmodel-scratch")
    )
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
        totalCasks: tokenToCategory.count,
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

    var startedWith: [Bool] = []
    var enabledChanges: [Bool] = []
    var capturedErrors: [Error] = []
    var breadcrumbs: [(message: String, data: [String: String])] = []
    var tags: [String: String] = [:]
    var spans: [SpanRecord] = []

    func start(enabled: Bool) {
        startedWith.append(enabled)
    }

    func setEnabled(_ enabled: Bool) {
        enabledChanges.append(enabled)
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
