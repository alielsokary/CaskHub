//
//  MaintenanceViewModel.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/08/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class MaintenanceViewModel {
    enum TaskState: Equatable {
        case idle
        case running
        case done
    }

    enum DiskCategoryID: String, CaseIterable, Identifiable, Sendable {
        case apps
        case cache
        case oldVersions
        case orphans
        case imageCache

        var id: String { rawValue }
    }

    // MARK: - Health

    private(set) var doctorRunning = false
    private(set) var checks: [HealthCheck] = []
    private(set) var lastChecked: Date?
    private(set) var advisoryCount: Int?
    var advisoriesExpanded = false

    // MARK: - Widgets

    enum Freshness: Equatable {
        case unknown
        case current
        case updateAvailable(String)
    }

    private(set) var homebrewState: TaskState = .idle
    private(set) var homebrewFailed = false
    private(set) var syncState: TaskState = .idle
    var brewFreshness: Freshness = .unknown
    var collectionFreshness: Freshness = .unknown

    // MARK: - Disk

    private(set) var diskScanning = false
    private(set) var hasDiskSnapshot = false
    private(set) var diskBytes: [DiskCategoryID: Int64] = [:]
    private(set) var rowStates: [DiskCategoryID: TaskState] = [:]
    private(set) var failedRows: Set<DiskCategoryID> = []
    private(set) var orphanFormulae: [String] = []
    private(set) var cachedInstallers: [CachedInstaller] = []
    var expandedRows: Set<DiskCategoryID> = []

    let localHomebrew: LocalHomebrewService
    let catalog: CaskCatalogViewModel
    private let clearImageCache: () async -> Void
    private let probe: any MaintenanceProbing
    let latestReleaseTag: (String, String) async -> String?
    let defaults: UserDefaults

    static let homebrewOperationToken = "caskhub-homebrew"
    private static let lastCheckedKey = "maintenanceLastChecked"
    private static let advisoryCountKey = "maintenanceAdvisoryCount"

    // ponytail: assumes the default cache path; HOMEBREW_CACHE overrides are not honored.
    nonisolated static let homebrewCacheDirectory: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Homebrew")

    init(
        localHomebrew: LocalHomebrewService,
        catalog: CaskCatalogViewModel,
        clearImageCache: @escaping () async -> Void,
        probe: any MaintenanceProbing = SystemMaintenanceProbe(),
        latestReleaseTag: @escaping (String, String) async -> String? = { owner, repo in
            await LatestReleaseChecker.latestTag(owner: owner, repo: repo)
        },
        defaults: UserDefaults = .standard
    ) {
        self.localHomebrew = localHomebrew
        self.catalog = catalog
        self.clearImageCache = clearImageCache
        self.probe = probe
        self.latestReleaseTag = latestReleaseTag
        self.defaults = defaults
        lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
        advisoryCount = defaults.object(forKey: Self.advisoryCountKey) as? Int
    }

    // MARK: - Health Checkup

    func runCheckup() async {
        guard !doctorRunning else { return }
        doctorRunning = true
        defer { doctorRunning = false }

        var nextChecks: [HealthCheck] = [brewInstallationCheck()]
        nextChecks.append(await commandLineToolsCheck())
        if let brewURL = localHomebrew.brewBinaryProvider(),
           let doctor = await probe.run(
               brewURL,
               arguments: ["doctor"],
               environment: BrewDoctorEnvironment.make(brewURL: brewURL)
           ) {
            nextChecks += BrewDoctorParser.warnings(from: doctor.output)
        }
        recordCheckup(nextChecks)
    }

    private func recordCheckup(_ nextChecks: [HealthCheck]) {
        checks = nextChecks
        let count = nextChecks.filter { $0.status == .advisory }.count
        advisoryCount = count
        advisoriesExpanded = true
        lastChecked = .now
        defaults.set(lastChecked, forKey: Self.lastCheckedKey)
        defaults.set(count, forKey: Self.advisoryCountKey)
    }

    private func brewInstallationCheck() -> HealthCheck {
        guard let brewURL = localHomebrew.brewBinaryProvider() else {
            return HealthCheck(
                id: "brew",
                status: .advisory,
                label: String(localized: .maintenanceCheckBrewLabel),
                detail: String(localized: .maintenanceCheckBrewFail)
            )
        }
        let prefix = HomebrewLocator.prefix(
            from: brewURL,
            fileManager: localHomebrew.fileManager
        ) ?? brewURL.deletingLastPathComponent().path
        return HealthCheck(
            id: "brew",
            status: .pass,
            label: String(localized: .maintenanceCheckBrewLabel),
            detail: String(localized: .maintenanceCheckBrewPass(
                localHomebrew.brewVersion ?? "?", prefix
            ))
        )
    }

    private func commandLineToolsCheck() async -> HealthCheck {
        let result = await probe.run(
            URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-p"]
        )
        let path = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let result, result.exitCode == 0, !path.isEmpty {
            return HealthCheck(
                id: "clt",
                status: .pass,
                label: String(localized: .maintenanceCheckCltLabel),
                detail: String(localized: .maintenanceCheckCltPass(path))
            )
        }
        return HealthCheck(
            id: "clt",
            status: .advisory,
            label: String(localized: .maintenanceCheckCltLabel),
            detail: String(localized: .maintenanceCheckCltFail)
        )
    }

    var healthSummary: String {
        if doctorRunning { return String(localized: .maintenanceHealthSummaryRunning) }
        guard let advisoryCount else {
            return String(localized: .maintenanceHealthSummaryNotRun)
        }
        return advisoryCount == 0
            ? String(localized: .maintenanceHealthSummaryAllClear)
            : String(localized: .maintenanceHealthSummaryAdvisories(advisoryCount))
    }

    var topBarSummary: String? {
        var parts: [String] = []
        if let advisoryCount {
            parts.append(advisoryCount == 0
                ? String(localized: .maintenanceSummaryAllClear)
                : String(localized: .maintenanceSummaryReview(advisoryCount)))
        }
        if let reclaimable = reclaimableBytes, reclaimable > 0 {
            parts.append(String(localized: .maintenanceSummaryReclaimable(
                MaintenanceFormat.bytes(reclaimable)
            )))
        }
        if let lastChecked {
            parts.append(String(localized: .maintenanceHealthCheckedAt(
                lastChecked.formatted(.relative(presentation: .named))
            )))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Widgets

    var brewVersion: String? { localHomebrew.brewVersion }
    var brewPrefix: String? {
        localHomebrew.brewBinaryProvider().flatMap {
            HomebrewLocator.prefix(from: $0, fileManager: localHomebrew.fileManager)
        }
    }

    var installedCount: Int { catalog.installedCount }
    var lastSyncedAt: Date? { catalog.lastLoadedAt }
    var hasActiveOperations: Bool { localHomebrew.hasActiveOperations }

    func updateHomebrew() async {
        guard homebrewState == .idle, !localHomebrew.hasActiveOperations else { return }
        homebrewFailed = false
        homebrewState = .running
        do {
            try await localHomebrew.updateHomebrew(for: Self.homebrewOperationToken)
            homebrewState = .done
            await refreshFreshness(force: true)
        } catch {
            homebrewState = .idle
            homebrewFailed = true
        }
    }

    func syncCollection() async {
        guard syncState != .running else { return }
        syncState = .running
        await catalog.load()
        syncState = .done
        await refreshFreshness(force: true)
    }
}

// MARK: - Disk

extension MaintenanceViewModel {
    func refreshDisk() async {
        guard !diskScanning else { return }
        diskScanning = true
        defer { diskScanning = false }

        let probe = probe
        async let cacheBytes = probe.directorySize(at: Self.homebrewCacheDirectory)
        async let installers = probe.cachedInstallers(at: Self.homebrewCacheDirectory)
        async let imageBytes = probe.directorySize(at: IconDiskCache.defaultDirectory)
        let appURLs = installedAppURLs()
        async let appsBytes = Self.totalSize(of: appURLs, probe: probe)

        if let brewURL = localHomebrew.brewBinaryProvider() {
            async let cleanup = probe.run(brewURL, arguments: ["cleanup", "--dry-run"])
            async let autoremove = probe.run(brewURL, arguments: ["autoremove", "--dry-run"])
            if let cleanupResult = await cleanup {
                setBytes(.oldVersions, BrewCleanupParser.supersededKegBytes(from: cleanupResult.output))
            }
            if let autoremoveResult = await autoremove {
                let names = BrewAutoremoveParser.formulae(from: autoremoveResult.output)
                orphanFormulae = names
                var total: Int64 = 0
                if let cellar = cellarURL, !names.isEmpty {
                    total = await Self.totalSize(
                        of: names.map { cellar.appendingPathComponent($0) },
                        probe: probe
                    )
                }
                // Floored so unmeasurable orphans still keep the row actionable.
                setBytes(.orphans, names.isEmpty ? 0 : max(total, 1))
            }
        } else {
            setBytes(.oldVersions, 0)
            setBytes(.orphans, 0)
        }
        setBytes(.cache, await cacheBytes)
        if rowStates[.cache, default: .idle] != .done {
            cachedInstallers = await installers
        }
        setBytes(.imageCache, await imageBytes)
        setBytes(.apps, await appsBytes)
        hasDiskSnapshot = true
    }

    func clean(_ id: DiskCategoryID) async {
        guard id != .apps, rowStates[id, default: .idle] == .idle else { return }
        // Brew mutates the same directories installs touch; stay out of its way.
        guard id == .imageCache || !localHomebrew.hasActiveOperations else { return }
        failedRows.remove(id)
        rowStates[id] = .running
        finishClean(id, succeeded: await performClean(id))
    }

    private func performClean(_ id: DiskCategoryID) async -> Bool {
        switch id {
        case .apps:
            return false
        case .cache:
            return await probe.removeDirectoryContents(at: Self.homebrewCacheDirectory)
        case .oldVersions:
            return await runBrew(["cleanup"])
        case .orphans:
            return await runBrew(["autoremove"])
        case .imageCache:
            await clearImageCache()
            return true
        }
    }

    private func finishClean(_ id: DiskCategoryID, succeeded: Bool) {
        guard succeeded else {
            rowStates[id] = .idle
            failedRows.insert(id)
            return
        }
        diskBytes[id] = 0
        if id == .orphans { orphanFormulae = [] }
        if id == .cache { cachedInstallers = [] }
        rowStates[id] = .done
    }

    var orderedDiskCategories: [DiskCategoryID] {
        DiskCategoryID.allCases.enumerated().sorted { lhs, rhs in
            let left = diskBytes[lhs.element] ?? 0
            let right = diskBytes[rhs.element] ?? 0
            if left != right { return left > right }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    var reclaimableBytes: Int64? {
        let known = [DiskCategoryID.cache, .oldVersions, .orphans, .imageCache]
            .compactMap { diskBytes[$0] }
        guard !known.isEmpty else { return nil }
        return known.reduce(0, +)
    }

    func directories(for id: DiskCategoryID) -> [URL] {
        switch id {
        case .apps:
            return localHomebrew.applicationDirectories + [caskroomURL].compactMap { $0 }
        case .cache:
            return [Self.homebrewCacheDirectory]
        case .oldVersions:
            return [caskroomURL, cellarURL].compactMap { $0 }
        case .orphans:
            return [cellarURL].compactMap { $0 }
        case .imageCache:
            return [IconDiskCache.defaultDirectory]
        }
    }

    // MARK: - Private

    private func runBrew(_ arguments: [String]) async -> Bool {
        guard let brewURL = localHomebrew.brewBinaryProvider(),
              let result = await probe.run(brewURL, arguments: arguments)
        else { return false }
        return result.exitCode == 0
    }

    private func setBytes(_ id: DiskCategoryID, _ value: Int64) {
        guard rowStates[id, default: .idle] != .done else { return }
        diskBytes[id] = value
    }

    private var caskroomURL: URL? {
        HomebrewLocator.caskroomURL(
            customPrefix: localHomebrew.customBrewPrefix,
            fileManager: localHomebrew.fileManager
        )
    }

    private var cellarURL: URL? {
        guard let brewURL = localHomebrew.brewBinaryProvider(),
              let prefix = HomebrewLocator.prefix(
                  from: brewURL,
                  fileManager: localHomebrew.fileManager
              )
        else { return nil }
        return URL(fileURLWithPath: prefix).appendingPathComponent("Cellar")
    }

    private func installedAppURLs() -> [URL] {
        let fileManager = localHomebrew.fileManager
        var urls: [URL] = []
        for installation in localHomebrew.installedCasks.values {
            for name in installation.appBundleNames {
                for directory in localHomebrew.applicationDirectories {
                    let candidate = directory.appendingPathComponent(name)
                    if fileManager.fileExists(atPath: candidate.path) {
                        urls.append(candidate)
                        break
                    }
                }
            }
        }
        return urls
    }

    private nonisolated static func totalSize(
        of urls: [URL],
        probe: any MaintenanceProbing
    ) async -> Int64 {
        await withTaskGroup(of: Int64.self, returning: Int64.self) { group in
            for url in urls {
                group.addTask { await probe.directorySize(at: url) }
            }
            var total: Int64 = 0
            for await size in group { total += size }
            return total
        }
    }
}
