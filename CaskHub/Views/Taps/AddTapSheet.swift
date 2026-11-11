//
//  AddTapSheet.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Observation
import SwiftUI

@MainActor
@Observable
final class AddTapModel {
    enum Phase: Equatable {
        case input
        case adding(TapAddRequest)
        case offerInstall(Cask)
        case notInTap(token: String, tap: String)
        case alreadyInstalled(token: String)
        case failed(String)
    }

    struct Environment {
        let addTap: (TapAddRequest) async throws -> Void
        let hasTap: (String) -> Bool
        let tapCask: (String) -> Cask?
        let isInstalled: (String) -> Bool
        let failureMessage: (String) -> String?
    }

    var text = ""
    private(set) var phase: Phase

    init(phase: Phase = .input) {
        self.phase = phase
    }

    var request: TapAddRequest? {
        try? TapAddInput.parse(text).get()
    }

    var canAdd: Bool {
        request != nil && phase == .input
    }

    var previewText: String? {
        request.map { String(localized: "Will tap \($0.tapName) from \(Self.source(of: $0))") }
    }

    var errorText: String? {
        guard case let .failure(error) = TapAddInput.parse(text) else { return nil }
        switch error {
        case .empty: return nil
        case .unrecognized: return String(localized: "Enter a tap like user/repo or a GitHub URL.")
        case .officialTap: return String(localized: "Homebrew's own taps are already included.")
        }
    }

    static func source(of request: TapAddRequest) -> String {
        if let remoteURL = request.remoteURL {
            return (remoteURL.host() ?? "") + remoteURL.path()
        }
        let parts = request.tapName.split(separator: "/")
        return "github.com/\(parts[0])/homebrew-\(parts[1])"
    }

    static func alreadyInstalledText(token: String) -> String {
        String(localized: "\(token) is already installed.")
    }

    static func notInTapText(token: String, tap: String) -> String {
        String(localized: "\(token) isn't in \(tap).")
    }

    /// Returns true when the sheet should close.
    func submit(_ environment: Environment) async -> Bool {
        guard let request, phase == .input else { return false }
        phase = .adding(request)
        do {
            try await environment.addTap(request)
        } catch is CancellationError {
            phase = .input
            return true
        } catch {
            phase = .failed(failureText(for: request, environment))
            return false
        }
        guard environment.hasTap(request.tapName) else {
            phase = .failed(failureText(for: request, environment))
            return false
        }
        guard let token = request.caskToken else { return true }
        let reference = "\(request.tapName)/\(token)"
        if environment.isInstalled(reference) {
            phase = .alreadyInstalled(token: token)
        } else if let cask = environment.tapCask(reference) {
            phase = .offerInstall(cask)
        } else {
            phase = .notInTap(token: token, tap: request.tapName)
        }
        return false
    }

    private func failureText(for request: TapAddRequest, _ environment: Environment) -> String {
        environment.failureMessage(LocalHomebrewService.tapOperationToken(request.tapName))
            ?? String(localized: "CaskHub couldn't add \(request.tapName).")
    }
}

struct AddTapSheet: View {
    let viewModel: CaskCatalogViewModel
    @State var model: AddTapModel

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(\.dismiss) private var dismiss

    init(viewModel: CaskCatalogViewModel, model: AddTapModel) {
        self.viewModel = viewModel
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.phase {
            case .input:
                inputContent
            case let .adding(request):
                addingContent(request)
            case let .offerInstall(cask):
                offerContent(cask)
            case let .notInTap(token, tap):
                message(title: String(localized: "Add a Tap"), body: AddTapModel.notInTapText(token: token, tap: tap))
            case let .failed(text):
                message(title: String(localized: "Add a Tap"), body: text)
            case let .alreadyInstalled(token):
                message(title: String(localized: "Add a Tap"), body: AddTapModel.alreadyInstalledText(token: token))
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Color.chSurfaceHero)
        .interactiveDismissDisabled(isAdding)
    }

    private var isAdding: Bool {
        if case .adding = model.phase { return true }
        return false
    }

    @ViewBuilder private var inputContent: some View {
        title(String(localized: "Add a Tap"))
        Text("Enter a tap name, a GitHub repository URL, or a brew install command.")
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
        Text("TAP NAME OR GITHUB URL")
            .font(CHType.labelSm)
            .kerning(CHType.trackingLabel)
            .foregroundStyle(Color.chTextMuted)
        TextField(text: $model.text, prompt: Text(verbatim: "hashicorp/tap")) { EmptyView() }
            .textFieldStyle(.roundedBorder)
            .font(CHType.statusMono)
            .onSubmit(submit)
        if let preview = model.previewText {
            Label { Text(verbatim: preview) } icon: { Image(systemName: "checkmark") }
                .font(CHType.bodySm)
                .foregroundStyle(Color.chActionInstallFg)
        } else if let error = model.errorText {
            Text(verbatim: error)
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextMuted)
        }
        Text("Examples: hashicorp/tap · github.com/user/homebrew-casks")
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)
        Text("Adding a tap doesn't trust it. Each cask asks before its first install.")
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)
        buttons {
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Add Tap", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canAdd)
        }
    }

    @ViewBuilder private func addingContent(_ request: TapAddRequest) -> some View {
        title(String(localized: "Adding \(request.tapName)…"))
        Text("Cloning the repository. Large taps can take a minute.")
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
        ProgressView()
            .progressViewStyle(.linear)
        Text(verbatim: "Cloning into …/Taps/\(AddTapModel.source(of: request).replacingOccurrences(of: "github.com/", with: ""))")
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)
            .lineLimit(1)
        buttons {
            Button("Cancel", role: .cancel) { localHomebrew.cancelAddTap(request.tapName) }
        }
    }

    @ViewBuilder private func offerContent(_ cask: Cask) -> some View {
        title(String(localized: "Install \(TrustInstallPrompt.safeLabel(cask.token))?"))
        Text(verbatim: TrustInstallPrompt(cask: cask).message)
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
        buttons {
            Button("Not Now", role: .cancel) { dismiss() }
            Button("Install") {
                localHomebrew.send(.confirmTrustedInstall(cask))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private func message(title text: String, body: String) -> some View {
        title(text)
        Text(verbatim: body)
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
        buttons {
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func title(_ text: String) -> some View {
        Text(verbatim: text)
            .font(CHType.section)
            .foregroundStyle(Color.chTextTitle)
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
        .padding(.top, 6)
    }

    private func submit() {
        let environment = AddTapModel.Environment(
            addTap: { try await viewModel.addTap($0) },
            hasTap: { [localHomebrew] name in localHomebrew.tapIndex.taps.contains { $0.name == name } },
            tapCask: { [localHomebrew] reference in localHomebrew.tapIndex.casks.first { $0.reference == reference } },
            isInstalled: { [localHomebrew] reference in
                localHomebrew.installationSnapshot.installedCasks[CaskReference.bareToken(reference)] != nil
            },
            failureMessage: { [localHomebrew] token in
                guard case let .failure(failure) = localHomebrew.actionAlert(for: token) else { return nil }
                localHomebrew.send(.dismissFailure(token: token))
                return failure.message
            }
        )
        Task {
            if await model.submit(environment) { dismiss() }
        }
    }
}
