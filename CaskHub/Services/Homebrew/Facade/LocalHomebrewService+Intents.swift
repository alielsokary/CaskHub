//
//  LocalHomebrewService+Intents.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

enum CaskIntent {
    case install(Cask)
    case confirmTrustedInstall(Cask)
    case cancelTrustedInstall
    case uninstall(token: String)
    case uninstallKeepingData(token: String)
    case trustAndUninstall(token: String, removingData: Bool)
    case repair(token: String)
    case repairAndReinstall(token: String)
    case forceUpgrade(token: String)
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
            homebrewInstallation: installationSnapshot.installation(for: cask.reference),
            operationState: operationStore.state(for: cask.reference),
            isHomebrewMutationBlocked: operationStore.isUpdatingHomebrew
        )
    }

    func send(_ intent: CaskIntent) {
        if handleMutationIntent(intent)
            || handleTrustIntent(intent)
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
            Task { try? await installRequestingTrust(cask) }
        case let .uninstall(token):
            Task { try? await uninstall(token: token) }
        case let .uninstallKeepingData(token):
            Task { try? await uninstallKeepingData(token: token) }
        case let .repair(token):
            Task { try? await repair(token: token) }
        case let .repairAndReinstall(token):
            Task { try? await repairReinstalling(token: token) }
        case let .forceUpgrade(token):
            Task { try? await forceUpgrade(token: token) }
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

    private func handleTrustIntent(_ intent: CaskIntent) -> Bool {
        switch intent {
        case let .confirmTrustedInstall(cask):
            Task { try? await confirmTrustedInstall(cask) }
        case .cancelTrustedInstall:
            pendingTrustInstall = nil
        case let .trustAndUninstall(token, removingData):
            Task { try? await trustAndUninstall(token: token, removingData: removingData) }
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
        case let .cancelAdoption(token),
             let .cancelPermission(token),
             let .dismissFailure(token):
            clearError(for: token)
        default:
            return false
        }
        return true
    }
}
