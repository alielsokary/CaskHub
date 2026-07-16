//
//  UpdaterService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/07/2026.
//

import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle's updater lifecycle: starts the standard updater controller
/// and exposes check state for menu items.
@Observable
final class UpdaterService {
    private let controller: SPUStandardUpdaterController
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var cancellable: AnyCancellable?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Mirrors Sparkle's own auto-check preference (persisted by Sparkle).
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

/// Menu item that stays disabled while Sparkle is mid-check.
struct CheckForUpdatesView: View {
    let updater: UpdaterService

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
