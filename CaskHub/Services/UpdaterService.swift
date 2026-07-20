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
    mutating func updateStaged(showPromptEnabled: Bool) {
        if showPromptEnabled { pending = true }
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
    static let showUpdatePromptKey = "showUpdatePromptAtLaunch"

    private var controller: SPUStandardUpdaterController!
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var cancellable: AnyCancellable?
    @ObservationIgnored private var stagedUpdate = StagedUpdateGate()

    override init() {
        super.init()
        UserDefaults.standard.register(defaults: [Self.showUpdatePromptKey: true])
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        // Sparkle allows a forced launch check here, before its scheduled cycle starts.
        Self.checkForUpdatesOnLaunch(using: controller.updater)
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in
                guard let self else { return }
                canCheckForUpdates = canCheck
                // Resume the staged update as a user-facing check: shows the
                // ready-to-install prompt with release notes, no re-download.
                if stagedUpdate.consumeResume(canCheck: canCheck) {
                    controller.updater.checkForUpdates()
                }
            }
    }

    static func checkForUpdatesOnLaunch(using updater: some BackgroundUpdateChecking) {
        guard updater.automaticallyChecksForUpdates else { return }
        updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
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
                showPromptEnabled: UserDefaults.standard.bool(forKey: Self.showUpdatePromptKey)
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
        .disabled(!updater.canCheckForUpdates)
    }
}
