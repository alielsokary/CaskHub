//
//  LocalHomebrewService+Intents.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

enum CaskIntent {
    case install(Cask)
    case uninstall(token: String)
    case repair(token: String)
    case repairAndReinstall(token: String)
    case updateHomebrew(token: String)
    case update(token: String)
    case updateAll(tokens: [String])
    case requestAdoption(Cask)
    case confirmAdoption(CaskAdoptionRequest)
    case requestReplacementAdoption(Cask)
    case open(Cask)
    case openExternal(Cask)
    case cancel(token: String)
    case cancelAdoption(token: String)
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
            operationState: operationStore.state(for: cask.token),
            isHomebrewMutationBlocked: operationStore.isUpdatingHomebrew
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
        case let .install(cask):
            Task { try? await install(cask) }
        case let .uninstall(token):
            Task { try? await uninstall(token: token) }
        case let .repair(token):
            Task { try? await repair(token: token) }
        case let .repairAndReinstall(token):
            Task { try? await repairReinstalling(token: token) }
        case let .updateHomebrew(token):
            Task { try? await updateHomebrew(for: token) }
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
        case let .requestAdoption(cask):
            Task { await requestAdoption(cask) }
        case let .confirmAdoption(request):
            Task { try? await confirmAdoption(request) }
        case let .requestReplacementAdoption(cask):
            Task { await requestReplacementAdoption(cask) }
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
        case let .cancelAdoption(token):
            cancelAdoptionRequest(token: token)
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
