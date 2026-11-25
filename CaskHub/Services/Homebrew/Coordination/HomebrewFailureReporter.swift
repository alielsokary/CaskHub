//
//  HomebrewFailureReporter.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/11/2026.
//

import Foundation

/// Sends a mutation's unrecovered failure to analytics and, when the issue policy allows it, to Sentry.
@MainActor
struct HomebrewFailureReporter {
    let operationStore: CaskOperationStore

    func record(
        _ error: Error,
        request: HomebrewMutationSequenceRequest,
        span: CrashSpan?,
        strandedCopyExists: Bool
    ) {
        span?.finish(error: error)
        let localError = error as? LocalHomebrewError
        Analytics.caskActionFailed(
            request.action,
            token: request.token,
            origin: request.origin,
            failureKind: localError?.failureKind
        )
        var tags = tags(for: request)
        // A failure about an existing stranded copy did not create it.
        if strandedCopyExists, localError?.failureKind != .strandedCaskroomApp {
            tags["brew.left_stranded_copy"] = "true"
            CrashReporter.capture(StrandedCopyDetected(
                subcommand: localError?.commandFailure?.subcommand ?? "missing",
                failureKind: localError?.failureKind
            ), tags: tags)
        }
        guard HomebrewIssuePolicy.shouldCapture(
            error,
            action: request.action,
            context: request.context
        ) else { return }
        CrashReporter.capture(error, tags: tags)
    }

    private func tags(for request: HomebrewMutationSequenceRequest) -> [String: String] {
        var tags = request.context.telemetryTags
        tags["brew.action"] = request.action.identifier
        tags["brew.cask"] = request.token
        tags["brew.tap"] = CaskReference.tap(of: request.token)
        tags["brew.origin"] = request.origin.rawValue
        if operationStore.state(for: request.token)?.cancellationRequested == true {
            tags["brew.cancellation_requested"] = "true"
        }
        return tags
    }
}
