//
//  LocalHomebrewService+Adoption.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func requestAdoption(_ cask: Cask) async {
        guard let plan = localState(for: cask).adoptionPlan else { return }
        await requestAdoption(CaskAdoptionRequest(cask: cask, plan: plan))
    }

    func requestReplacementAdoption(_ cask: Cask) async {
        let localPlan = localState(for: cask).adoptionPlan
        let artifact: CaskAdoptionArtifact = cask.hasPackageArtifact
            ? .packageInstaller
            : .applicationBundle
        let plan = CaskAdoptionPlan(
            artifact: artifact,
            versionRelationship: localPlan?.versionRelationship ?? .unknown,
            operation: localPlan?.operation ?? .adopt,
            execution: artifact == .packageInstaller
                ? .replacePackage
                : .replaceApplication,
            installedVersion: localPlan?.installedVersion,
            homebrewVersion: cask.displayVersion,
            blockingInstalledCask: localPlan?.blockingInstalledCask
        )
        await requestAdoption(CaskAdoptionRequest(cask: cask, plan: plan))
    }

    func confirmAdoption(_ request: CaskAdoptionRequest) async throws {
        guard await requireAdoptionPermission(for: request) else { return }
        guard preflightAdoption(request) else { return }

        switch request.plan.execution {
        case .adoptApplication:
            try await runMutation(
                .adopting,
                token: request.cask.token,
                args: ["install", "--cask", request.cask.token, "--adopt"]
            )
        case .replaceApplication:
            try await runMutation(
                .adopting,
                token: request.cask.token,
                args: ["install", "--cask", request.cask.token, "--force"]
            )
        case .installPackage:
            try await runMutation(
                .adopting,
                token: request.cask.token,
                args: ["install", "--cask", request.cask.token]
            )
        case .replacePackage:
            try await replacePackageForAdoption(token: request.cask.token)
        }
    }

    /// A linked artifact missing from the on-disk bundle makes Homebrew fail
    /// after it has moved the app aside. Its rollback can then remove the only
    /// copy. Check every bundle-relative link source before `--adopt` runs.
    func adoptBlockedByMissingComponent(_ cask: Cask) -> String? {
        guard let appURL = existingBundleURL(named: cask.appArtifactNames) else {
            return nil
        }
        let marker = "\(appURL.lastPathComponent)/"
        for path in cask.adoptionSourcePaths {
            guard let range = path.range(of: marker) else { continue }
            let relativePath = String(path[range.upperBound...])
            let resolved = appURL.appendingPathComponent(relativePath)
            if !fileManager.fileExists(atPath: resolved.path) {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return nil
    }

    /// Called after returning from System Settings. Permission approval resumes
    /// at confirmation; it never starts a destructive replacement implicitly.
    func resumePendingAdoptions() {
        let pending = operationStore.pendingPermissions
        guard !pending.isEmpty else { return }
        Task {
            guard await permissionAllowsAdoption() else { return }
            for (token, request) in pending {
                guard preflightAdoption(request) else { continue }
                operationStore.send(.awaitAdoption(request), for: token)
            }
        }
    }

    private func requestAdoption(_ request: CaskAdoptionRequest) async {
        guard preflightAdoption(request) else { return }
        guard await requireAdoptionPermission(for: request) else { return }
        operationStore.send(.awaitAdoption(request), for: request.cask.token)
    }

    private func preflightAdoption(_ request: CaskAdoptionRequest) -> Bool {
        if let conflict = request.plan.blockingInstalledCask {
            operationStore.send(
                .fail(CaskOperationFailure(
                    kind: .adoptionPreflight,
                    message: "\(request.cask.displayName) conflicts with the Homebrew-managed "
                        + "cask “\(conflict)”. Uninstall that cask before adopting this one."
                )),
                for: request.cask.token
            )
            return false
        }
        guard request.plan.execution == .adoptApplication,
              let missing = adoptBlockedByMissingComponent(request.cask)
        else { return true }

        let message = String(
            localized: .errorAdoptMissingComponent(
                request.cask.displayName,
                missing
            )
        )
        operationStore.send(
            .fail(CaskOperationFailure(
                kind: .adoptionPreflight,
                message: message,
                recoveries: [.replaceWithHomebrew]
            )),
            for: request.cask.token
        )
        return false
    }

    private func requireAdoptionPermission(
        for request: CaskAdoptionRequest
    ) async -> Bool {
        guard await permissionAllowsAdoption() else {
            operationStore.send(
                .awaitPermission(request),
                for: request.cask.token
            )
            return false
        }
        return true
    }

    /// Adoption only proceeds after the probe positively demonstrates access.
    /// An indeterminate probe stays gated because it cannot prove Homebrew can
    /// modify the existing application.
    private func permissionAllowsAdoption() async -> Bool {
        let probe = permissionProbe
        let status = await Task.detached(priority: .userInitiated) { probe() }.value
        return status == .granted
    }
}
