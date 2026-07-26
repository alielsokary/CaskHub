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

        case let LocalHomebrewError.brewCommandFailed(arguments, _, stderr):
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

        default:
            break
        }

        return CaskOperationFailure(
            kind: kind,
            message: message,
            recoveries: recoveries
        )
    }
}
