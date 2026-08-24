//
//  LocalHomebrewService+Adoption.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func requestAdoption(_ cask: Cask) async {
        guard let request = currentAdoptionRequest(for: cask, intent: .planned) else {
            return
        }
        await requestAdoption(request)
    }

    func requestReplacementAdoption(_ cask: Cask) async {
        guard let request = currentAdoptionRequest(for: cask, intent: .replacement) else {
            return
        }
        await requestAdoption(request)
    }

    func confirmAdoption(_ request: CaskAdoptionRequest) async throws {
        await refresh()
        guard let current = currentAdoptionRequest(
            for: request.cask,
            intent: request.intent
        ) else {
            operationStore.send(.clear, for: request.cask.token)
            return
        }
        guard current == request else {
            operationStore.send(.awaitAdoption(current), for: request.cask.token)
            return
        }
        guard let permission = await requireAdoptionPermission(
            for: request,
            allowUnverified: true
        ) else {
            return
        }
        guard preflightAdoption(request) else { return }
        let context = HomebrewMutationContext(
            adoptionPlan: request.plan, permissionEvidence: permission.evidence
        )

        switch request.plan.execution {
        case .adoptApplication:
            try await runMutation(
                .adopting,
                token: request.cask.token,
                args: ["install", "--cask", request.cask.token, "--adopt"],
                context: context
            )
        case .replaceApplication:
            try await runMutation(
                .adopting,
                token: request.cask.token,
                args: ["install", "--cask", request.cask.token, "--force"],
                context: context
            )
        case .installPackage:
            try await runMutation(
                .adopting,
                token: request.cask.token,
                args: ["install", "--cask", request.cask.token],
                context: context
            )
        case .replacePackage:
            try await replacePackageForAdoption(
                token: request.cask.token,
                context: context
            )
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
    func resumePendingAdoptions() async {
        let pending = operationStore.pendingPermissions
        guard !pending.isEmpty else { return }
        for (token, request) in pending {
            guard let current = currentAdoptionRequest(
                for: request.cask,
                intent: request.intent
            ) else {
                operationStore.send(.clear, for: token)
                continue
            }
            let assessment = await permissionAssessment(for: current)
            guard assessment.status != .denied else { continue }
            guard preflightAdoption(current) else { continue }
            operationStore.send(.awaitAdoption(current), for: token)
        }
    }

    private func requestAdoption(_ request: CaskAdoptionRequest) async {
        guard preflightAdoption(request) else { return }
        guard await requireAdoptionPermission(for: request) != nil else { return }
        operationStore.send(.awaitAdoption(request), for: request.cask.token)
    }

    private func preflightAdoption(_ request: CaskAdoptionRequest) -> Bool {
        if let conflict = request.cask.conflictsWith?.caskTokens
            .filter({ installedCasks[$0] != nil })
            .sorted()
            .first {
            Analytics.caskActionFailed(
                .adopting,
                token: request.cask.token,
                failureKind: .caskConflict
            )
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
        Analytics.caskActionFailed(
            .adopting,
            token: request.cask.token,
            failureKind: .missingArtifactSource
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
        for request: CaskAdoptionRequest,
        allowUnverified: Bool = false
    ) async -> AppManagementPermission.Assessment? {
        let assessment = await permissionAssessment(for: request)
        switch assessment.status {
        case .granted:
            return assessment
        case .unknown where allowUnverified:
            return AppManagementPermission.Assessment(
                status: .unknown,
                evidence: .unverified
            )
        case .denied, .unknown:
            operationStore.send(
                .awaitPermission(request),
                for: request.cask.token
            )
            return nil
        }
    }

    /// The exact scanner-owned bundle is stronger evidence than a catalog name.
    /// macOS has no public query API, so an unprobeable target can proceed only
    /// after the user returns from Settings and confirms the adoption again.
    private func permissionAssessment(
        for request: CaskAdoptionRequest
    ) async -> AppManagementPermission.Assessment {
        let probe = permissionProbe
        let bundle = installationSnapshot
            .externalPackageApplicationOwners[request.cask.token]?.url
            ?? installationSnapshot.externalApplicationOwners[request.cask.token]?.url
            ?? existingBundleURL(named:
                request.cask.packageAppNameCandidates + request.cask.appArtifactNames
            )
        let assessment = await Task.detached(priority: .userInitiated) {
            probe(bundle)
        }.value
        return assessment
    }

    private func currentAdoptionRequest(
        for cask: Cask,
        intent: CaskAdoptionIntent
    ) -> CaskAdoptionRequest? {
        let state = localState(for: cask)
        let current = state.adoptionPlan
        let plan: CaskAdoptionPlan
        switch intent {
        case .planned:
            guard let current else { return nil }
            plan = current
        case .replacement:
            let artifact = current?.artifact ?? (cask.hasPackageArtifact
                ? .packageInstaller
                : .applicationBundle)
            plan = CaskAdoptionPlan(
                artifact: artifact,
                versionRelationship: current?.versionRelationship ?? .unknown,
                operation: current?.operation ?? .adopt,
                execution: artifact == .packageInstaller
                    ? .replacePackage
                    : .replaceApplication,
                installedVersion: current?.installedVersion,
                homebrewVersion: current?.homebrewVersion ?? cask.displayVersion,
                blockingInstalledCask: current?.blockingInstalledCask
            )
        }
        return CaskAdoptionRequest(cask: cask, intent: intent, plan: plan)
    }
}
