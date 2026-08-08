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
        strandedCopyExists: Bool
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

        case let LocalHomebrewError.brewCommandFailed(arguments, exitCode, stderr):
            if LocalHomebrewError.isAppManagementDenial(stderr: stderr) {
                kind = .appManagementDenied
                recoveries.insert(.openAppManagementSettings)
            }
            if LocalHomebrewError.isAdoptMismatch(
                args: arguments,
                stderr: stderr
            ), !LocalHomebrewError.isStrandedApp(stderr: stderr) {
                recoveries.insert(.replaceWithHomebrew)
            }
            if LocalHomebrewError.isStrandedApp(stderr: stderr)
                || (arguments.first == "upgrade" && strandedCopyExists) {
                recoveries.insert(.repairAndReinstall)
            }
            recoveries.formUnion(classRecoveries(
                failureClass: LocalHomebrewError.failureClass(stderr: stderr, exitCode: exitCode),
                arguments: arguments,
                stderr: stderr
            ))

        default:
            break
        }

        return CaskOperationFailure(
            kind: kind,
            message: message,
            recoveries: recoveries
        )
    }

    private static func classRecoveries(
        failureClass: String,
        arguments: [String],
        stderr: String
    ) -> Set<CaskRecoveryAction> {
        switch failureClass {
        case "binary-conflict":
            return [.replaceWithHomebrew]
        case "app-conflict":
            // No adopt retry after a failed --adopt.
            let canAdopt = arguments.first == "install" && !arguments.contains("--adopt")
            return canAdopt ? [.adoptExisting, .replaceWithHomebrew] : [.replaceWithHomebrew]
        case "missing-uninstall-script":
            // Fires on upgrades too — a bare force-uninstall there strands the user.
            switch arguments.first {
            case "uninstall": return [.forceUninstall]
            case "upgrade": return [.repairAndReinstall]
            default: return []
            }
        case "missing-artifact-source"
            where arguments.first == "upgrade" && !stderr.contains("Caskroom"):
            // A missing Caskroom staging path is a broken download; reinstall can't help.
            return [.repairAndReinstall]
        default:
            return []
        }
    }
}
