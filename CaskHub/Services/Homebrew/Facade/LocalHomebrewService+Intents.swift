//
//  LocalHomebrewService+Intents.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

enum CaskIntent {
    case install(token: String)
    case uninstall(token: String)
    case repair(token: String)
    case repairAndReinstall(token: String)
    case update(token: String)
    case updateAll(tokens: [String])
    case adopt(Cask)
    case requestPackageAdoption(token: String)
    case confirmPackageAdoption(token: String)
    case replaceWithHomebrew(token: String)
    case adoptAnyway(token: String, force: Bool)
    case open(Cask)
    case openExternal(Cask)
    case cancel(token: String)
    case cancelPackageAdoption(token: String)
    case cancelPermission(token: String)
    case dismissFailure(token: String)
}

extension LocalHomebrewService {
    func actionAlert(for token: String) -> CaskActionAlert? {
        CaskActionAlert.make(operationState: operationStore.state(for: token))
    }

    func actionPresentation(
        for cask: Cask,
        localState suppliedState: CaskLocalState? = nil
    ) -> CaskActionPresentation {
        CaskActionPresentation(
            localState: suppliedState ?? localState(for: cask),
            homebrewInstallation: installationSnapshot.installedCasks[cask.token],
            operationState: operationStore.state(for: cask.token)
        )
    }

    func send(_ intent: CaskIntent) {
        if handleMutationIntent(intent)
            || handleAdoptionIntent(intent)
            || handleOpenIntent(intent)
            || handleOperationStateIntent(intent) {
            return
        }
        assertionFailure("Unhandled CaskIntent")
    }

    private func handleMutationIntent(_ intent: CaskIntent) -> Bool {
        switch intent {
        case let .install(token):
            Task { try? await install(token: token) }
        case let .uninstall(token):
            Task { try? await uninstall(token: token) }
        case let .repair(token):
            Task { try? await repair(token: token) }
        case let .repairAndReinstall(token):
            Task { try? await repairReinstalling(token: token) }
        case let .update(token):
            Task { try? await upgrade(token: token) }
        case let .updateAll(tokens):
            Task { await updateAll(tokens: tokens) }
        default:
            return false
        }
        return true
    }

    private func handleAdoptionIntent(_ intent: CaskIntent) -> Bool {
        switch intent {
        case let .adopt(cask):
            Task { try? await adopt(cask) }
        case let .requestPackageAdoption(token):
            requestPackageAdoption(token: token)
        case let .confirmPackageAdoption(token):
            Task { try? await adoptPackage(token: token) }
        case let .replaceWithHomebrew(token):
            Task { try? await adoptReplacing(token: token) }
        case let .adoptAnyway(token, force):
            cancelPermissionRequest(token: token)
            Task {
                if force {
                    try? await adoptReplacing(token: token, bypassPermissionCheck: true)
                } else {
                    try? await adopt(token: token, bypassPermissionCheck: true)
                }
            }
        default:
            return false
        }
        return true
    }

    private func handleOpenIntent(_ intent: CaskIntent) -> Bool {
        switch intent {
        case let .open(cask):
            open(cask)
        case let .openExternal(cask):
            openExternalApp(cask: cask)
        default:
            return false
        }
        return true
    }

    private func handleOperationStateIntent(_ intent: CaskIntent) -> Bool {
        switch intent {
        case let .cancel(token):
            cancelInstall(token: token)
        case let .cancelPackageAdoption(token):
            cancelPackageAdoptionRequest(token: token)
        case let .cancelPermission(token):
            cancelPermissionRequest(token: token)
        case let .dismissFailure(token):
            clearError(for: token)
        default:
            return false
        }
        return true
    }
}
