//
//  CaskHubApp.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/02/2026.
//

import AppKit
import SwiftUI

@main
enum CaskHubMain {
    static func main() {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--askpass") {
            let token = CommandLine.arguments.indices.contains(flagIndex + 1)
                ? CommandLine.arguments[flagIndex + 1] : nil
            Askpass.runDialog(token: token)
        }
        NSWindow.allowsAutomaticWindowTabbing = false
        CaskHubApp.main()
    }
}

struct CaskHubApp: App {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue
    @NSApplicationDelegateAdaptor(ApplicationTerminationCoordinator.self)
    private var terminationCoordinator

    @State private var updaterService = UpdaterService()
    @State private var helpTopic: HelpTopic = .gettingStarted
    @State private var settingsSection: SettingsSection = .general

    @State private var categoryService: CategoryService
    @State private var recentlyAdded: RecentlyAddedService
    @State private var localHomebrew: LocalHomebrewService
    @State private var imageCache: ImageCacheService
    @State private var catalog: CaskCatalogViewModel

    init() {
        // Tooltip delay in ms; registered (not set) so it never persists to prefs.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])
        BrandFonts.register()
        CrashReporter.start()
        Analytics.start()
        AppTheme.apply(UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue)

        // ~920KB of bundled JSON — keep it off the launch path.
        let categories = CategoryService()
        let recent = RecentlyAddedService()
        Task {
            await categories.loadBundledCategoriesAsync()
            await recent.loadBundledDatesAsync()
        }
        let homebrew = LocalHomebrewService()
        let images = ImageCacheService()
        images.knownIconTokens = { categories.iconTokens }
        _imageCache = State(initialValue: images)
        _categoryService = State(initialValue: categories)
        _recentlyAdded = State(initialValue: recent)
        _localHomebrew = State(initialValue: homebrew)
        _catalog = State(initialValue: CaskCatalogViewModel(
            apiClient: BrewAPIClient(),
            categoryService: categories,
            recentlyAdded: recent,
            localHomebrew: homebrew
        ))
    }

    var body: some Scene {
        Window("CaskHub", id: CaskHubWindowID.main) {
            ContentView(viewModel: catalog)
                .frame(minWidth: 1380, minHeight: 640)
                .background {
                    WindowCloseButtonConfigurator {
                        terminationCoordinator.requestTermination()
                    }
                }
                .background {
                    CaskHubHelpSearchRegistration(selection: $helpTopic)
                }
                .onAppear {
                    terminationCoordinator.configure {
                        localHomebrew.hasActiveOperations
                    }
                }
                .onChange(of: selectedTheme, initial: true) { _, newValue in
                    AppTheme.apply(newValue)
                }
                .environment(categoryService)
                .environment(recentlyAdded)
                .environment(localHomebrew)
                .environment(imageCache)
        }
        .defaultSize(width: 1360, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commandsRemoved()
        .commands {
            CommandGroup(replacing: .newItem) {}
            CaskHubApplicationCommands(updater: updaterService)
            CaskHubViewCommands()
            CaskHubHelpCommands(selection: $helpTopic)
        }

        Window("CaskHub Help", id: CaskHubWindowID.help) {
            CaskHubHelpView(
                selection: $helpTopic,
                settingsSelection: $settingsSection,
                navigateToCatalog: { catalog.selectedSidebar = $0 }
            )
            .environment(localHomebrew)
            .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 880, height: 620)
        .windowResizability(.contentMinSize)
        .commandsRemoved()
        .commands {
            CaskHubApplicationCommands(updater: updaterService)
            CaskHubHelpCommands(selection: $helpTopic)
        }

        Settings {
            SettingsView(selection: $settingsSection)
                .environment(updaterService)
                .environment(imageCache)
                .environment(localHomebrew)
        }
        .commands {
            CaskHubApplicationCommands(updater: updaterService)
            CaskHubHelpCommands(selection: $helpTopic)
        }
    }
}

@MainActor
struct WindowCloseButtonConfigurator: NSViewRepresentable {
    typealias CloseAction = @MainActor @Sendable () -> Void

    let onClose: CloseAction

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeNSView(context: Context) -> WindowObservationView {
        let view = WindowObservationView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: WindowObservationView, context: Context) {
        view.coordinator = context.coordinator
        context.coordinator.onClose = onClose
        if let window = view.window {
            context.coordinator.attach(to: window)
        }
    }

    static func dismantleNSView(_ view: WindowObservationView, coordinator: Coordinator) {
        view.coordinator = nil
        coordinator.detach()
    }

    @MainActor
    final class WindowObservationView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                coordinator?.attach(to: window)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onClose: CloseAction

        private weak var closeButton: NSButton?
        private weak var originalTarget: AnyObject?
        private var originalAction: Selector?

        init(onClose: @escaping CloseAction) {
            self.onClose = onClose
        }

        func detach() {
            guard let closeButton, closeButton.target === self else { return }
            closeButton.target = originalTarget
            closeButton.action = originalAction
            self.closeButton = nil
            originalTarget = nil
            originalAction = nil
        }

        func attach(to window: NSWindow) {
            guard let button = window.standardWindowButton(.closeButton) else { return }
            guard closeButton !== button || button.target !== self else { return }

            detach()
            closeButton = button
            originalTarget = button.target
            originalAction = button.action
            button.target = self
            button.action = #selector(closeButtonPressed)
        }

        @objc
        private func closeButtonPressed() {
            onClose()
        }
    }
}
