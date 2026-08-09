//
//  LocalHomebrewService+Adoption.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func requestPackageAdoption(token: String) {
        operationStore.send(.awaitPackageAdoption, for: token)
    }

    func cancelPackageAdoptionRequest(token: String) {
        operationStore.send(.clear, for: token)
    }

    /// Package artifacts do not support Homebrew's `--adopt` semantics. Running
    /// the package installer again is the supported path that creates Homebrew's
    /// Caskroom records and transfers future management to Homebrew.
    func adoptPackage(token: String) async throws {
        try await runMutation(
            .adopting,
            token: token,
            args: ["install", "--cask", token]
        )
    }

    /// Preflight before `--adopt`: a declared binary missing from the on-disk
    /// bundle makes brew fail *after* it has moved the app aside — and brew's
    /// rollback then deletes the app entirely. Refuse locally and offer the
    /// safe replace path instead.
    func adopt(_ cask: Cask, bypassPermissionCheck: Bool = false) async throws {
        if let missing = adoptBlockedByMissingBinary(cask) {
            let message = String(
                localized: """
                Your installed copy of \(cask.displayName) is missing a component \
                Homebrew's version includes (\(missing)), so it can't be adopted \
                as-is. You can replace it with Homebrew's copy instead — your \
                settings and data are kept.
                """
            )
            operationStore.send(
                .fail(CaskOperationFailure(
                    kind: .adoptionPreflight,
                    message: message,
                    recoveries: [.replaceWithHomebrew]
                )),
                for: cask.token
            )
            return
        }
        try await adopt(token: cask.token, bypassPermissionCheck: bypassPermissionCheck)
    }

    /// Only paths inside the app bundle can be preflighted; staged-path binaries
    /// don't exist until brew downloads the cask, so they're skipped.
    func adoptBlockedByMissingBinary(_ cask: Cask) -> String? {
        guard let appURL = existingBundleURL(named: cask.appArtifactNames) else { return nil }
        let marker = "/\(appURL.lastPathComponent)/"
        for path in cask.binarySourcePaths {
            guard let range = path.range(of: marker) else { continue }
            let resolved = appURL.appendingPathComponent(String(path[range.upperBound...]))
            if !fileManager.fileExists(atPath: resolved.path) {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return nil
    }

    func adopt(token: String, bypassPermissionCheck: Bool = false) async throws {
        if !bypassPermissionCheck, await !permissionAllowsAdoption() {
            operationStore.send(.awaitPermission(force: false), for: token)
            return
        }
        try await runMutation(.adopting, token: token, args: ["install", "--cask", token, "--adopt"])
    }

    /// Fallback when `--adopt` refuses: replace the on-disk app with Homebrew's copy.
    /// Needs App Management even more than adopt — brew deletes the existing app,
    /// and a TCC-denied delete makes brew escalate to a scary sudo password prompt.
    func adoptReplacing(token: String, bypassPermissionCheck: Bool = false) async throws {
        if !bypassPermissionCheck, await !permissionAllowsAdoption() {
            operationStore.send(.awaitPermission(force: true), for: token)
            return
        }
        try await runMutation(.adopting, token: token, args: ["install", "--cask", token, "--force"])
    }

    func cancelPermissionRequest(token: String) {
        operationStore.send(.clear, for: token)
    }

    /// Called when the app becomes active: if the user granted App Management while
    /// away (in System Settings), finish the adoptions that were waiting on it.
    func resumePendingAdoptions() {
        let pending = operationStore.pendingPermissions
        guard !pending.isEmpty else { return }
        Task {
            guard await permissionAllowsAdoption() else { return }
            for (token, useForce) in pending {
                if useForce {
                    try? await adoptReplacing(token: token, bypassPermissionCheck: true)
                } else {
                    try? await adopt(token: token, bypassPermissionCheck: true)
                }
            }
        }
    }

    /// `.unknown` passes through — only a confirmed denial blocks, so a failed
    /// probe can never lock the user out of adopting.
    private func permissionAllowsAdoption() async -> Bool {
        let probe = permissionProbe
        let status = await Task.detached(priority: .userInitiated) { probe() }.value
        return status != .denied
    }
}
