//
//  LocalHomebrewService+Taps.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

extension LocalHomebrewService {
    static let lastTapUpdateKey = "lastTapUpdateAt"

    static func tapOperationToken(_ tapName: String) -> String {
        "caskhub-tap:\(tapName)"
    }

    func refreshTaps() async {
        guard let index = await tapIndexProvider() else { return }
        tapIndex = index
    }

    /// Where an installed cask's app should be, from brew's receipt; no disk access, so views may call it.
    func installedAppCandidates(for cask: Cask) -> [URL] {
        guard let installation = installationSnapshot.installation(for: cask.reference) else { return [] }
        return installation.appBundleNames.flatMap { name in
            applicationDirectories.map { $0.appendingPathComponent(name) }
        }
    }

    func isTrusted(_ cask: Cask) -> Bool {
        tapIndex.trusts(cask.reference)
    }

    /// A tap cask's first install waits for `confirmTrustedInstall`; brew trusts it on install.
    /// Trust is re-read first: `brew uninstall` drops a cask's trust, so the cached list goes stale.
    func installRequestingTrust(_ cask: Cask) async throws {
        if cask.thirdPartyTap != nil {
            let trust = await tapTrustProvider()
            tapIndex = TapIndex(taps: tapIndex.taps, casks: tapIndex.casks, trust: trust)
        }
        guard isTrusted(cask) else {
            pendingTrustInstall = cask
            return
        }
        try await install(cask)
    }

    func confirmTrustedInstall(_ cask: Cask) async throws {
        pendingTrustInstall = nil
        defer { Task { await refreshTaps() } }
        try await install(cask)
    }

    func addTap(_ request: TapAddRequest) async throws {
        let token = Self.tapOperationToken(request.tapName)
        cancelledTapAdds.remove(request.tapName)
        try await runMutationSequence(
            .addingTap,
            token: token,
            steps: [.exclusive(request.brewArguments, cancellation: .untilPerforming)],
            origin: .individual,
            displayName: request.tapName
        )
        await refreshTaps()
        // The coordinator swallows cancellation, so the cancel request itself is the signal.
        guard cancelledTapAdds.remove(request.tapName) != nil else { return }
        if tapIndex.taps.contains(where: { $0.name == request.tapName }) {
            try? await runMutation(.removingTap, token: token, args: ["untap", request.tapName])
            await refreshTaps()
        }
        throw CancellationError()
    }

    func cancelAddTap(_ tapName: String) {
        cancelledTapAdds.insert(tapName)
        cancelInstall(token: Self.tapOperationToken(tapName))
    }

    func removalPreview(for tapName: String) async -> TapRemovalPreview {
        let casks = installationSnapshot.installedCasks.values
            .filter { $0.tap == tapName }
            .sorted { $0.token < $1.token }
            .map { installation in
                tapIndex.casks.first { $0.reference == CaskReference.make(token: installation.token, tap: tapName) }
                    ?? Cask.receiptRow(for: installation)
            }
        return TapRemovalPreview(
            tapName: tapName,
            installedCasks: casks,
            installedFormulae: await installedFormulaeProvider(tapName)
        )
    }

    func removeTap(_ preview: TapRemovalPreview) async throws {
        try await runMutationSequence(
            .removingTap,
            token: Self.tapOperationToken(preview.tapName),
            steps: [.exclusive(["untap"] + (preview.removesInstalledItems ? ["--force"] : []) + [preview.tapName], cancellation: .never)],
            origin: .individual,
            displayName: preview.tapName
        )
        await refreshTaps()
        await refreshHomebrewOutdated()
    }

    /// Pulls every tap so tap-cask updates appear; never runs beside a cask operation.
    func updateTapsIfStale(now: Date, maxAge: TimeInterval) async {
        guard !operationStore.hasActiveOperations else { return }
        if let last = defaults.object(forKey: Self.lastTapUpdateKey) as? Date,
           now.timeIntervalSince(last) < maxAge {
            return
        }
        defaults.set(now, forKey: Self.lastTapUpdateKey)
        guard await lanes.acquire(.exclusive, token: nil, onWait: {}) else { return }
        await tapUpdateProvider()
        lanes.release(.exclusive)
        await refresh()
        await refreshTaps()
        await refreshHomebrewOutdated()
    }
}
