//
//  CaskOperationFailureFactory.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

enum CaskOperationFailureFactory {
    static func make(
        from error: Error,
        strandedCopyExists: Bool,
        title: String? = nil
    ) -> CaskOperationFailure {
        let message = (error as? LocalHomebrewError)?.errorDescription
            ?? error.localizedDescription
        var kind = CaskOperationFailure.Kind.brewCommand
        var recoveries: Set<CaskRecoveryAction> = []

        switch error {
        case LocalHomebrewError.brewBinaryNotFound:
            kind = .homebrewMissing

        case LocalHomebrewError.appBundleNotFound:
            kind = .applicationUnavailable

        case let LocalHomebrewError.brewCommandFailed(failure):
            let arguments = failure.arguments
            let stderr = failure.diagnostic
            if failure.kind == .permissionDenied {
                kind = .appManagementDenied
                recoveries.insert(.openAppManagementSettings)
            }
            if failure.kind == .adoptVersionMismatch {
                recoveries.insert(.replaceWithHomebrew)
            }
            if failure.kind == .strandedCaskroomApp
                || (arguments.first == "upgrade" && strandedCopyExists) {
                recoveries.insert(.repairAndReinstall)
            }
            recoveries.formUnion(classRecoveries(
                failureKind: failure.kind,
                arguments: arguments,
                stderr: stderr
            ))

        default:
            break
        }

        return CaskOperationFailure(
            kind: kind,
            message: message,
            title: title,
            recoveries: recoveries
        )
    }

    private static func classRecoveries(
        failureKind: HomebrewFailureKind,
        arguments: [String],
        stderr: String
    ) -> Set<CaskRecoveryAction> {
        switch failureKind {
        case .packageNewerInstalled, .packageAlreadyInstalled, .packageUpgradeFailed:
            return [.replaceWithHomebrew]
        case .binaryConflict:
            return [.replaceWithHomebrew]
        case .appConflict:
            // No adopt retry after a failed --adopt.
            let canAdopt = arguments.first == "install" && !arguments.contains("--adopt")
            return canAdopt ? [.adoptExisting, .replaceWithHomebrew] : [.replaceWithHomebrew]
        case .missingUninstallScript:
            // Fires on upgrades too — a bare force-uninstall there strands the user.
            switch arguments.first {
            case "uninstall": return [.forceUninstall]
            case "upgrade": return [.repairAndReinstall]
            default: return []
            }
        case .missingArtifactSource
            where arguments.first == "upgrade" && !stderr.contains("Caskroom"):
            // A missing Caskroom staging path is a broken download; reinstall can't help.
            return [.repairAndReinstall]
        case .homebrewRuntimeIncompatible:
            return [.updateHomebrew]
        default:
            return []
        }
    }
}
