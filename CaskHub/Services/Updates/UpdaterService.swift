//
//  UpdaterService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/07/2026.
//

import Combine
import Sparkle
import SwiftUI

protocol BackgroundUpdateChecking {
    var automaticallyChecksForUpdates: Bool { get }
    func checkForUpdatesInBackground()
}

extension SPUUpdater: BackgroundUpdateChecking {}

// Tracks an update Sparkle silently staged in the background so it can be
// surfaced as a user-facing prompt once the update session ends. Pure state,
// so the resume decision is testable without a live SPUUpdater.
struct StagedUpdateGate {
    private(set) var pending = false

    // Called when a background check staged an update for install-on-quit.
    mutating func updateStaged(automaticChecksEnabled: Bool) {
        if automaticChecksEnabled { pending = true }
    }

    // checkForUpdates() is a no-op mid-session, so we wait for canCheck to flip
    // true. Returns true exactly once per staged update, then clears.
    mutating func consumeResume(canCheck: Bool) -> Bool {
        guard canCheck, pending else { return false }
        pending = false
        return true
    }
}

@Observable
final class UpdaterService: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private(set) var canCheckForUpdates = false
    private(set) var isCheckingForUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var stagedUpdate = StagedUpdateGate()

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        // Sparkle allows a forced launch check here, before its scheduled cycle starts.
        Self.checkForUpdatesOnLaunch(using: controller.updater)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in
                guard let self else { return }
                canCheckForUpdates = canCheck
                if canCheck { isCheckingForUpdates = false }
                // Resume the staged update as a user-facing check: shows the
                // ready-to-install prompt with release notes, no re-download.
                if stagedUpdate.consumeResume(canCheck: canCheck) {
                    controller.updater.checkForUpdates()
                }
            }
            .store(in: &cancellables)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] date in
                self?.lastUpdateCheckDate = date
            }
            .store(in: &cancellables)
    }

    static func checkForUpdatesOnLaunch(using updater: some BackgroundUpdateChecking) {
        guard updater.automaticallyChecksForUpdates else { return }
        updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        isCheckingForUpdates = !controller.updater.sessionInProgress
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // Fires only when a background check silently downloaded and staged an
    // update for install-on-quit (SPUAutomaticUpdateDriver). Returning false
    // keeps Sparkle's install-on-quit behavior either way; the flag is picked
    // up by the canCheckForUpdates sink once this update session winds down —
    // checkForUpdates() is a no-op while a session is still in progress.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Sparkle calls delegate methods on the main thread.
        MainActor.assumeIsolated {
            stagedUpdate.updateStaged(
                automaticChecksEnabled: updater.automaticallyChecksForUpdates
            )
        }
        return false
    }
}

struct CheckForUpdatesView: View {
    let updater: UpdaterService

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
    }
}
