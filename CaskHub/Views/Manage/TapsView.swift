//
//  TapsView.swift
//  CaskHub
//

import SwiftUI

struct TapsView: View {
    let viewModel: CaskCatalogViewModel
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var tapName = ""
    @State private var remote = ""
    @State private var showsRemote = false
    @State private var isWorking = false
    @State private var isRefreshing = false
    @State private var note: TapNote?
    @State private var tapPendingRemoval: HomebrewTap?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                addCard
                tapsCard
            }
            .frame(maxWidth: CHSize.contentWidth, alignment: .leading)
            .padding(.horizontal, CHSpace.s5)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.top, CHSpace.belowToolbar, for: .scrollContent)
        .toolbarScrollEdge()
        .contentMargins(.bottom, 44, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            String(localized: "Remove this tap?"),
            isPresented: Binding(
                get: { tapPendingRemoval != nil },
                set: { if !$0 { tapPendingRemoval = nil } }
            ),
            presenting: tapPendingRemoval
        ) { tap in
            Button(String(localized: "Remove \(tap.name)"), role: .destructive) {
                remove(tap)
            }
        } message: { tap in
            Text("Casks from \(tap.name) will no longer appear in CaskHub. Installed apps are kept, and Homebrew refuses to untap while any of them is still installed.")
        }
    }

    // MARK: - Add

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a tap")
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text("Taps are extra Homebrew repositories. Enter user/repo to add one from GitHub, as you would with brew tap.")
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextBody)
            HStack(spacing: 10) {
                TextField("", text: $tapName, prompt: Text("user/repo"))
                    .labelsHidden()
                    .accessibilityLabel("Tap name")
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .disabled(isWorking)
                    .onSubmit(add)
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                PillButton(
                    title: String(localized: "Add Tap"),
                    background: .chActionInstallBg,
                    border: .chActionInstallBorder,
                    foreground: .chActionInstallFg,
                    action: add
                )
                .disabled(isWorking || tapName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            DisclosureGroup("Custom remote", isExpanded: $showsRemote) {
                TextField("", text: $remote, prompt: Text("https://example.com/homebrew-tap.git"))
                    .labelsHidden()
                    .accessibilityLabel("Tap remote URL")
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .disabled(isWorking)
            }
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
            if let note {
                Text(note.message)
                    .font(CHType.bodySm)
                    .foregroundStyle(note.isFailure ? Color.chActionUpdateFg : Color.chActionDoneFg)
                    .textSelection(.enabled)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    // MARK: - Taps

    private var tapsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Your taps")
                    .font(CHType.section)
                    .foregroundStyle(Color.chTextTitle)
                Spacer(minLength: 10)
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
                PillButton(
                    title: String(localized: "Refresh Taps"),
                    background: .chSurfaceField,
                    border: .chHairlineStrong,
                    foreground: .chTextNav,
                    action: refresh
                )
                .disabled(isWorking || isRefreshing)
            }
            .padding(.bottom, 10)
            if localHomebrew.taps.isEmpty {
                Text(localHomebrew.hasLoadedTaps ? "No third-party taps yet." : "Loading taps…")
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
            } else {
                ForEach(localHomebrew.taps) { tap in
                    tapRow(tap)
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
        .glassPanel()
    }

    private func tapRow(_ tap: HomebrewTap) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tap.name)
                    .font(CHType.cardTitle)
                    .foregroundStyle(Color.chTextTitle)
                Text("\(tap.caskTokens.count) casks")
                    .font(CHType.statusMono)
                    .foregroundStyle(Color.chTextFaint)
            }
            .lineLimit(1)
            Spacer(minLength: 10)
            PillButton(
                title: String(localized: "Browse"),
                background: .chSurfaceField,
                border: .chHairlineStrong,
                foreground: .chTextNav
            ) {
                viewModel.selectedSidebar = .tap(tap.name)
            }
            .disabled(tap.caskTokens.isEmpty)
            PillButton(
                title: String(localized: "Remove"),
                background: .chActionUpdateBg,
                border: .chActionUpdateBorder,
                foreground: .chActionUpdateFg
            ) {
                tapPendingRemoval = tap
            }
            .disabled(isWorking || isRefreshing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }

    // MARK: - Actions

    private func add() {
        let name = tapName
        let customRemote = showsRemote ? remote.trimmingCharacters(in: .whitespaces) : ""
        guard !isWorking, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isWorking = true
        note = nil
        Task {
            let result = await viewModel.addTap(name, remote: customRemote.isEmpty ? nil : customRemote)
            isWorking = false
            if result.succeeded {
                tapName = ""
                remote = ""
                note = TapNote(message: String(localized: "Tap added."), isFailure: false)
            } else {
                note = TapNote(message: failureMessage(result), isFailure: true)
            }
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        note = nil
        Task {
            let result = await viewModel.updateTaps()
            isRefreshing = false
            note = result.succeeded
                ? TapNote(message: String(localized: "Taps are up to date."), isFailure: false)
                : TapNote(message: failureMessage(result), isFailure: true)
        }
    }

    private func remove(_ tap: HomebrewTap) {
        isWorking = true
        note = nil
        Task {
            let result = await viewModel.removeTap(tap.name)
            isWorking = false
            if result.succeeded {
                if viewModel.selectedSidebar == .tap(tap.name) {
                    viewModel.selectedSidebar = .taps
                }
                note = TapNote(message: String(localized: "Tap removed."), isFailure: false)
            } else {
                note = TapNote(message: failureMessage(result), isFailure: true)
            }
        }
    }

    private func failureMessage(_ result: HomebrewTapCommandResult) -> String {
        result.output.isEmpty ? String(localized: "Homebrew could not complete this request.") : result.output
    }
}

private struct TapNote {
    let message: String
    let isFailure: Bool
}

struct TapsSettingsView: View {
    @Environment(CaskCatalogViewModel.self) private var viewModel
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(ImageCacheService.self) private var imageCache
    @State private var tapName = ""
    @State private var remote = ""
    @State private var isWorking = false
    @State private var note: TapNote?

    var body: some View {
        Form {
            Section("Add a tap") {
                TextField("Tap", text: $tapName, prompt: Text("user/repo"))
                    .font(.body.monospaced())
                    .onSubmit(add)
                TextField("Custom remote (optional)", text: $remote, prompt: Text("https://example.com/homebrew-tap.git"))
                    .font(.body.monospaced())
                HStack {
                    Button("Add Tap", action: add)
                        .disabled(isWorking || tapName.trimmingCharacters(in: .whitespaces).isEmpty)
                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                }
                if let note {
                    Text(note.message)
                        .foregroundStyle(note.isFailure ? Color.red : Color.green)
                        .textSelection(.enabled)
                }
            }
            Section {
                if localHomebrew.taps.isEmpty {
                    Text(localHomebrew.hasLoadedTaps ? "No third-party taps yet." : "Loading taps…")
                        .foregroundStyle(.secondary)
                }
                ForEach(localHomebrew.taps) { tap in
                    LabeledContent(tap.name, value: "\(tap.caskTokens.count) casks")
                    HStack {
                        Spacer()
                        Button("Remove", role: .destructive) { remove(tap) }
                            .disabled(isWorking)
                    }
                }
            } header: {
                Text("Your taps")
            }
            Section("Maintenance") {
                HStack {
                    Button("Refresh Taps", action: refresh)
                        .disabled(isWorking)
                    Button("Reset Icon Cache") {
                        isWorking = true
                        Task {
                            await imageCache.clearCache()
                            isWorking = false
                            note = TapNote(message: String(localized: "Icon cache reset."), isFailure: false)
                        }
                    }
                    .disabled(isWorking)
                }
                Text("Tap apps use the installed app's icon, or Icons/<token>.png from the tap's GitHub repository. Reset the icon cache after pushing a new icon.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            if !localHomebrew.hasLoadedTaps { await viewModel.refreshTaps() }
        }
    }

    private func add() {
        let customRemote = remote.trimmingCharacters(in: .whitespaces)
        let name = tapName
        guard !isWorking, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        run {
            await viewModel.addTap(name, remote: customRemote.isEmpty ? nil : customRemote)
        } successMessage: {
            tapName = ""
            remote = ""
            return String(localized: "Tap added.")
        }
    }

    private func refresh() {
        run { await viewModel.updateTaps() } successMessage: {
            String(localized: "Taps are up to date.")
        }
    }

    private func remove(_ tap: HomebrewTap) {
        run { await viewModel.removeTap(tap.name) } successMessage: {
            if viewModel.selectedSidebar == .tap(tap.name) { viewModel.selectedSidebar = .taps }
            return String(localized: "Tap removed.")
        }
    }

    private func run(
        _ work: @escaping () async -> HomebrewTapCommandResult,
        successMessage: @escaping () -> String
    ) {
        isWorking = true
        note = nil
        Task {
            let result = await work()
            isWorking = false
            note = result.succeeded
                ? TapNote(message: successMessage(), isFailure: false)
                : TapNote(
                    message: result.output.isEmpty
                        ? String(localized: "Homebrew could not complete this request.")
                        : result.output,
                    isFailure: true
                )
        }
    }
}
