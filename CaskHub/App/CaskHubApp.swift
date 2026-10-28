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
            let marker = argument(after: "--askpass-cancel-marker").map {
                URL(fileURLWithPath: $0)
            }
            Askpass.runDialog(token: token, cancellationMarker: marker)
        }
        NSWindow.allowsAutomaticWindowTabbing = false
        CaskHubApp.main()
    }

    private static func argument(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        return CommandLine.arguments[index + 1]
    }
}

struct CaskHubApp: App {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue
    @AppStorage(AppStyle.storageKey) private var selectedStyle: AppStyle = .classic
    @NSApplicationDelegateAdaptor(ApplicationTerminationCoordinator.self)
    private var terminationCoordinator

    @State private var updaterService = UpdaterService()
    @State private var helpTopic: HelpTopic = .gettingStarted
    @State private var settingsSection: SettingsSection = .general
    @State private var launchCard: LaunchCard?

    @State private var categoryService: CategoryService
    @State private var recentlyAdded: RecentlyAddedService
    @State private var localHomebrew: LocalHomebrewService
    @State private var imageCache: ImageCacheService
    @State private var catalog: CaskCatalogViewModel
    @State private var maintenance: MaintenanceViewModel

    init() {
        // Tooltip delay in ms; registered (not set) so it never persists to prefs.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])
        if CrashReporter.detectsTestRun { SilentTestRun.install() }
        // Must run before anything persists prefs or caches, or a new install reads as an upgrade.
        let hadPriorInstall = AppStyle.hasPriorInstall()
        AppStyle.current = AppStyle.resolveStored(in: .standard) { hadPriorInstall }
        _launchCard = State(initialValue: CrashReporter.isRunningTests ? nil : LaunchCardGate.resolve(
            in: .standard,
            currentVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            hasPriorInstall: hadPriorInstall,
            latestVersion: WhatsNewRelease.latest.version
        ))
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
        let catalogModel = CaskCatalogViewModel(
            apiClient: BrewAPIClient(),
            categoryService: categories,
            recentlyAdded: recent,
            localHomebrew: homebrew
        )
        _catalog = State(initialValue: catalogModel)
        _maintenance = State(initialValue: MaintenanceViewModel(
            localHomebrew: homebrew,
            catalog: catalogModel,
            clearImageCache: { await images.clearCache() }
        ))
    }

    var body: some Scene {
        Group {
            Window("CaskHub", id: CaskHubWindowID.main) {
                ContentView(viewModel: catalog)
                    .frame(minWidth: 900, minHeight: 500)
                    .background {
                        WindowCloseButtonConfigurator(
                            onClose: { terminationCoordinator.requestTermination() },
                            onBecomeKey: { updaterService.start() }
                        )
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
                    .onChange(of: selectedStyle) { _, newValue in
                        AppStyle.current = newValue
                    }
                    .sheet(item: $launchCard) { card in
                        LaunchCardView(card: card)
                    }
                    .environment(categoryService)
                    .environment(recentlyAdded)
                    .environment(localHomebrew)
                    .environment(imageCache)
                    .environment(maintenance)
            }
            .defaultSize(width: 1360, height: 880)
            .windowToolbarStyle(.unified(showsTitle: false))
            .commandsRemoved()
            .commands {
                CommandGroup(replacing: .newItem) {}
                CaskHubViewCommands()
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

            Settings {
                SettingsView(selection: $settingsSection)
                    .environment(updaterService)
                    .environment(localHomebrew)
                    .environment(catalog)
                    .environment(imageCache)
            }
        }
        .commands {
            CaskHubApplicationCommands(updater: updaterService)
            CaskHubHelpCommands(selection: $helpTopic, launchCard: $launchCard)
        }
    }
}

@MainActor
struct WindowCloseButtonConfigurator: NSViewRepresentable {
    typealias WindowAction = @MainActor @Sendable () -> Void

    let onClose: WindowAction
    let onBecomeKey: WindowAction

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose, onBecomeKey: onBecomeKey)
    }

    func makeNSView(context: Context) -> WindowObservationView {
        let view = WindowObservationView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: WindowObservationView, context: Context) {
        view.coordinator = context.coordinator
        context.coordinator.onClose = onClose
        context.coordinator.onBecomeKey = onBecomeKey
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
        var onClose: WindowAction
        var onBecomeKey: WindowAction

        private weak var observedWindow: NSWindow?
        private weak var closeButton: NSButton?
        private weak var originalTarget: AnyObject?
        private var originalAction: Selector?

        init(onClose: @escaping WindowAction, onBecomeKey: @escaping WindowAction) {
            self.onClose = onClose
            self.onBecomeKey = onBecomeKey
        }

        func detach() {
            if let closeButton, closeButton.target === self {
                closeButton.target = originalTarget
                closeButton.action = originalAction
            }
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didBecomeKeyNotification,
                    object: observedWindow
                )
            }
            observedWindow = nil
            self.closeButton = nil
            originalTarget = nil
            originalAction = nil
        }

        func attach(to window: NSWindow) {
            guard observedWindow !== window else { return }

            detach()
            observedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            if window.isKeyWindow {
                onBecomeKey()
            }

            guard let button = window.standardWindowButton(.closeButton) else { return }
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

        @objc
        private func windowDidBecomeKey() {
            onBecomeKey()
        }
    }
}

@MainActor
enum SilentTestRun {
    private static var observer: (any NSObjectProtocol)?

    static func install() {
        guard observer == nil else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                (notification.object as? NSWindow)?.alphaValue = 0
            }
        }
    }
}
