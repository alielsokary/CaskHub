//
//  ShelfSetupView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/08/2026.
//

import SwiftUI

enum ShelfSetupPicker: String, Identifiable {
    case adoptIgnore
    case pin

    var id: String { rawValue }
}

struct ShelfSetupView: View {
    let viewModel: CaskCatalogViewModel
    @State private var picker: ShelfSetupPicker?
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var exportNote: BrewfileNote?
    @State private var importNote: BrewfileNote?
    @State private var importPlan: BrewfileImportPlan?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brewfileCard
                PinnedUpdatesCard(viewModel: viewModel, picker: $picker)
                ignoreCard
            }
            .frame(maxWidth: CHSize.contentWidth, alignment: .leading)
            .padding(.horizontal, CHSpace.s5)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.top, CHSpace.belowToolbar, for: .scrollContent)
        .toolbarScrollEdge()
        .contentMargins(.bottom, 44, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .sheet(item: $picker) { picker in
            switch picker {
            case .adoptIgnore: AdoptIgnorePickerSheet(viewModel: viewModel)
            case .pin: PinPickerSheet(viewModel: viewModel)
            }
        }
        .sheet(item: $importPlan) { plan in
            BrewfileImportSheet(plan: plan, addTap: { try await viewModel.addTap($0) })
        }
    }

    // MARK: - Brewfile

    private var brewfileCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: .shelfSetupBrewfileTitle))
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
                .padding(.bottom, 10)
            brewfileRow(
                title: String(localized: .shelfSetupBrewfileExportTitle),
                description: String(
                    localized: .shelfSetupBrewfileExportDescription(viewModel.installedCount)
                ),
                note: exportNote
            ) {
                PillButton(
                    title: String(localized: .shelfSetupBrewfileExportButton),
                    background: .chActionInstallBg,
                    border: .chActionInstallBorder,
                    foreground: .chActionInstallFg,
                    action: exportBrewfile
                )
            }
            brewfileRow(
                title: String(localized: .shelfSetupBrewfileImportTitle),
                description: String(localized: .shelfSetupBrewfileImportDescription),
                note: importNote
            ) {
                PillButton(
                    title: String(localized: .shelfSetupBrewfileImportButton),
                    background: .chSurfaceField,
                    border: .chHairlineStrong,
                    foreground: .chTextNav,
                    action: chooseImportFile
                )
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
        .glassPanel()
    }

    private func brewfileRow(
        title: String,
        description: String,
        note: BrewfileNote?,
        @ViewBuilder button: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CHType.cardTitle)
                    .foregroundStyle(Color.chTextTitle)
                Text(description)
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextBody)
                if let note {
                    Text(note.message)
                        .font(CHType.bodySm)
                        .foregroundStyle(
                            note.isFailure ? Color.chActionUpdateFg : Color.chActionDoneFg
                        )
                }
            }
            Spacer(minLength: 10)
            button()
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }

    private func exportBrewfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Brewfile"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.showsHiddenFiles = true
        let response = CrashReporter.withHangTrackingPaused { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }
        let tokens = viewModel.installedCasks.map(\.reference)
        do {
            try Brewfile.contents(forCaskReferences: tokens)
                .write(to: url, atomically: true, encoding: .utf8)
            exportNote = BrewfileNote(
                message: String(localized: .shelfSetupBrewfileExportSaved(
                    (url.path as NSString).abbreviatingWithTildeInPath,
                    tokens.count
                )),
                isFailure: false
            )
        } catch {
            exportNote = BrewfileNote(
                message: String(localized: .shelfSetupBrewfileExportFailed),
                isFailure: true
            )
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        let response = CrashReporter.withHangTrackingPaused { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let tokens = Brewfile.caskTokens(in: contents)
        guard !tokens.isEmpty else {
            importNote = BrewfileNote(
                message: String(localized: .shelfSetupBrewfileImportEmpty),
                isFailure: true
            )
            return
        }
        importNote = nil
        importPlan = makeImportPlan(
            fileName: (url.path as NSString).abbreviatingWithTildeInPath,
            tokens: tokens,
            taps: Brewfile.taps(in: contents)
        )
    }

    // MARK: - Ignore List

    private var ignoreCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(String(localized: .shelfSetupIgnoreTitle))
                    .font(CHType.section)
                    .foregroundStyle(Color.chTextTitle)
                Spacer(minLength: 10)
                PillButton(
                    title: String(localized: .shelfSetupIgnoreAddButton),
                    background: .chSurfaceField,
                    border: .chHairlineStrong,
                    foreground: .chTextNav
                ) {
                    picker = .adoptIgnore
                }
            }
            Text(String(localized: .shelfSetupIgnoreDescription))
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextMuted)
                .padding(.top, 2)
                .padding(.bottom, 8)

            if viewModel.adoptIgnoredCasks.isEmpty {
                Text(String(localized: .shelfSetupIgnoreEmpty))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
            } else {
                ForEach(viewModel.adoptIgnoredCasks) { cask in
                    ignoredRow(cask)
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy, value: viewModel.adoptIgnoredCasks.map(\.reference))
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
        .glassPanel()
    }

    private func ignoredRow(_ cask: Cask) -> some View {
        HStack(spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cask.displayName)
                    .font(CHType.cardTitle)
                    .foregroundStyle(Color.chTextTitle)
                Text(cask.token)
                    .font(CHType.statusMono)
                    .foregroundStyle(Color.chTextFaint)
            }
            .lineLimit(1)
            Spacer(minLength: 10)
            if let when = localHomebrew.adoptIgnoredDates[cask.token] {
                Text(String(localized: .shelfSetupIgnoreIgnoredWhen(
                    when.formatted(.relative(presentation: .named))
                )))
                .font(CHType.statusMono)
                .foregroundStyle(Color.chTextFaint)
            }
            PillButton(
                title: String(localized: "Restore"),
                background: .chActionDoneBg,
                border: .chActionDoneBorder,
                foreground: .chActionDoneFg
            ) {
                localHomebrew.setAdoptIgnored(cask.token, false)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}

extension ShelfSetupView {
    func makeImportPlan(
        fileName: String,
        tokens: [String],
        taps: BrewfileTaps
    ) -> BrewfileImportPlan {
        let snapshot = viewModel.localHomebrew.installationSnapshot
        let existingTaps = Set(viewModel.localHomebrew.tapIndex.taps.map(\.name))
        // A tap already on this Mac keeps its own remote, so its casks stay installable.
        let unsupportedTaps = taps.unsupported.filter { !existingTaps.contains($0) }
        var skippedEntries: [BrewfileImportPlan.Entry] = []
        var newEntries: [BrewfileImportPlan.Entry] = []
        var unavailableEntries: [BrewfileImportPlan.Entry] = []
        var unsupportedTapEntries: [BrewfileImportPlan.Entry] = []
        for token in tokens {
            let entry = BrewfileImportPlan.Entry(token: token, cask: viewModel.catalogCask(for: CaskReference.normalized(token)))
            let state = entry.cask.map(viewModel.localState(for:))
            // Any install of this token, including a same-token twin, owns the Caskroom entry.
            if state?.isPresent == true || snapshot.installedCasks[CaskReference.bareToken(entry.reference)] != nil {
                skippedEntries.append(entry)
            } else if let tap = entry.tap, unsupportedTaps.contains(tap) || (try? TapAddInput.parse(tap).get()) == nil {
                // brew would auto-tap an unparsable tap from GitHub on install, so it never reaches brew.
                unsupportedTapEntries.append(entry)
            } else if state?.retirement?.blocksInstall == true {
                unavailableEntries.append(entry)
            } else {
                newEntries.append(entry)
            }
        }
        let impliedTaps = newEntries.compactMap { $0.tap.flatMap { try? TapAddInput.parse($0).get() } }
        var seen: Set<String> = []
        return BrewfileImportPlan(
            fileName: fileName,
            skippedEntries: skippedEntries,
            newEntries: newEntries,
            unavailableEntries: unavailableEntries,
            unsupportedTapEntries: unsupportedTapEntries,
            tapsToAdd: (taps.toAdd + impliedTaps).filter { !existingTaps.contains($0.tapName) && seen.insert($0.tapName).inserted },
            unsupportedTaps: unsupportedTaps
        )
    }
}

// MARK: - Picker Sheet

struct AdoptIgnorePickerSheet: View {
    let viewModel: CaskCatalogViewModel
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: .shelfSetupIgnorePickerTitle))
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text(String(localized: .shelfSetupIgnorePickerSubtitle))
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextBody)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.adoptableCasks.isEmpty {
                        Text(String(localized: .shelfSetupIgnorePickerEmpty))
                            .font(CHType.bodySm)
                            .foregroundStyle(Color.chTextMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
                    } else {
                        ForEach(viewModel.adoptableCasks) { cask in
                            adoptableRow(cask)
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.snappy, value: viewModel.adoptableCasks.map(\.reference))
            }
            .frame(height: 300)

            HStack {
                Spacer()
                PillButton(
                    title: String(localized: "Done"),
                    background: .chSurfaceField,
                    border: .chHairlineStrong,
                    foreground: .chTextNav
                ) {
                    dismiss()
                }
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 400)
        .background(Color.chSurfaceHero)
    }

    private func adoptableRow(_ cask: Cask) -> some View {
        HStack(spacing: 10) {
            CaskIconView(cask: cask, size: 28, alignment: .center)
            Text(cask.displayName)
                .font(CHType.cardTitle)
                .foregroundStyle(Color.chTextTitle)
                .lineLimit(1)
            Spacer(minLength: 10)
            PillButton(
                title: String(localized: "Ignore"),
                background: .chActionUpdateBg,
                border: .chActionUpdateBorder,
                foreground: .chActionUpdateFg
            ) {
                localHomebrew.setAdoptIgnored(cask.token, true)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}

#Preview {
    let categories = CategoryService()
    let recent = RecentlyAddedService()
    let homebrew = LocalHomebrewService()
    ShelfSetupView(viewModel: CaskCatalogViewModel(
        apiClient: BrewAPIClient(),
        categoryService: categories,
        recentlyAdded: recent,
        localHomebrew: homebrew
    ))
    .environment(homebrew)
    .environment(ImageCacheService())
    .frame(width: 1100, height: 600)
    .background(WindowBackdrop())
}
