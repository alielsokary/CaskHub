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
        case noCasks(tap: String)
        case failed(String)
    }

    struct Environment {
        let addTap: (TapAddRequest) async throws -> Void
        let hasTap: (String) -> Bool
        let hasCasks: (String) -> Bool
        let tapCask: (String) -> Cask?
        let isInstalled: (String) -> Bool
        let failureMessage: (String) -> String?
    }

    var text = ""
    private(set) var phase: Phase
    /// The cask named by a pasted install command, kept after the field is rewritten to `brew tap`.
    private var pastedCask: (tap: String, token: String)?

    init(phase: Phase = .input) {
        self.phase = phase
    }

    var request: TapAddRequest? {
        guard let parsed = try? TapAddInput.parse(text).get() else { return nil }
        guard parsed.caskToken == nil, let pastedCask, pastedCask.tap == parsed.tapName else { return parsed }
        return TapAddRequest(tapName: parsed.tapName, remoteURL: parsed.remoteURL, caskToken: pastedCask.token)
    }

    /// Only a paste (several characters at once) is rewritten, never typing in progress.
    func rewriteForPaste(from old: String, to new: String) -> TapCommandRewrite? {
        guard new.count - old.count > 1, let rewrite = TapAddInput.tapCommandRewrite(for: new) else { return nil }
        pastedCask = (rewrite.tapName, rewrite.caskToken)
        return rewrite
    }

    /// The field stays highlighted while there is text that doesn't parse yet.
    var isAwaitingMatch: Bool {
        !text.isEmpty && request == nil
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

    static func noCasksText(tap: String) -> String {
        String(localized: "\(tap) has no casks. CaskHub shows casks only for now.")
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
        guard let token = request.caskToken else {
            guard environment.hasCasks(request.tapName) else {
                phase = .noCasks(tap: request.tapName)
                return false
            }
            return true
        }
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
    @State private var rewrite: TapCommandRewrite?
    @State private var rewriteSettled = false

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
            case let .noCasks(tap):
                message(title: String(localized: "Add a Tap"), body: AddTapModel.noCasksText(tap: tap))
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
        tapField
        if let request = model.request {
            Label {
                previewText(for: request)
            } icon: {
                Image(systemName: "checkmark")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.chActionDoneFg)
            }
            .font(CHType.bodySm)
        } else if let error = model.errorText {
            Text(verbatim: error)
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextMuted)
        }
        Text("Examples: user/repo · github.com/user/homebrew-repo")
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)
        Text("Adding a tap doesn't trust it. Each cask asks before its first install.")
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)
        buttons {
            TapSheetPill.neutral(String(localized: "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            TapSheetPill.primary(String(localized: "Add Tap"), action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canAdd)
                .opacity(model.canAdd ? 1 : 0.45)
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
            TapSheetPill.neutral(String(localized: "Cancel")) { localHomebrew.cancelAddTap(request.tapName) }
        }
    }

    @ViewBuilder private func offerContent(_ cask: Cask) -> some View {
        title(String(localized: "Install \(TrustInstallPrompt.safeLabel(cask.token))?"))
        Text(verbatim: TrustInstallPrompt(cask: cask).message)
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
        buttons {
            TapSheetPill.neutral(String(localized: "Not Now")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            TapSheetPill.primary(String(localized: "Install")) {
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
            TapSheetPill.primary(String(localized: "Done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Matches the toolbar search field's focus ring: one soft accent ring outside a hairline border.
    private var tapField: some View {
        TextField(text: $model.text, prompt: Text(verbatim: "user/repo")) { EmptyView() }
            .textFieldStyle(.plain)
            .font(CHType.body)
            .foregroundStyle(rewrite == nil ? Color.primary : Color.clear)
            .overlay(alignment: .leading) {
                if let rewrite {
                    CommandRewriteText(rewrite: rewrite, settled: rewriteSettled)
                        .font(CHType.body)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.chSurfaceField))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.chHairlineStrong, lineWidth: 1))
            .overlay(
                RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                    .stroke(Color.chAccent.opacity(model.isAwaitingMatch ? 0.65 : 0), lineWidth: 3)
                    .padding(-2.5)
            )
            .animation(.easeOut(duration: 0.15), value: model.isAwaitingMatch)
            .onSubmit(submit)
            .onChange(of: model.text) { old, new in
                if let rewrite = model.rewriteForPaste(from: old, to: new) { play(rewrite) }
            }
    }

    private func play(_ next: TapCommandRewrite) {
        rewrite = next
        rewriteSettled = false
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(duration: 0.5)) { rewriteSettled = true }
            try? await Task.sleep(for: .milliseconds(600))
            model.text = next.finalText
            rewrite = nil
        }
    }

    /// Only the tap name is green, so it reads as the thing being matched.
    private func previewText(for request: TapAddRequest) -> Text {
        let name = Text(verbatim: request.tapName)
            .foregroundStyle(Color.chActionDoneFg)
            .fontWeight(.semibold)
        return Text("Will tap \(name) from \(AddTapModel.source(of: request))")
            .foregroundStyle(Color.chTextNav)
    }

    private func title(_ text: String) -> some View {
        Text(verbatim: text)
            .font(CHType.section)
            .foregroundStyle(Color.chTextTitle)
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Spacer()
            content()
        }
        .padding(.top, 6)
    }

    private func submit() {
        let environment = AddTapModel.Environment(
            addTap: { try await viewModel.addTap($0) },
            hasTap: { [localHomebrew] name in localHomebrew.tapIndex.taps.contains { $0.name == name } },
            hasCasks: { [localHomebrew] name in localHomebrew.tapIndex.tapsWithCasks.contains { $0.name == name } },
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

/// Shelf Setup's pill buttons, so tap sheets match the rest of Manage.
enum TapSheetPill {
    static func neutral(_ title: String, action: @escaping () -> Void) -> PillButton {
        PillButton(title: title, background: .chSurfaceField, border: .chHairlineStrong, foreground: .chTextNav, action: action)
    }

    static func primary(_ title: String, action: @escaping () -> Void) -> PillButton {
        PillButton(
            title: title, background: .chActionInstallBg, border: .chActionInstallBorder,
            foreground: .chActionInstallFg, action: action
        )
    }
}

/// The pasted install command losing its install words and cask name, the rest sliding left into `brew tap`.
private struct CommandRewriteText: View {
    let rewrite: TapCommandRewrite
    let settled: Bool

    private var collapse: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.01, anchor: .leading))
    }

    var body: some View {
        HStack(spacing: 0) {
            if !rewrite.keptPrefix.isEmpty {
                Text(verbatim: rewrite.keptPrefix + " ")
            }
            if settled {
                Text(verbatim: rewrite.addedWords + " ").transition(.opacity)
            } else if !rewrite.removedWords.isEmpty {
                Text(verbatim: rewrite.removedWords + " ").transition(collapse)
            }
            Text(verbatim: rewrite.tapName)
            if !settled {
                Text(verbatim: rewrite.removedSuffix).transition(collapse)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(Color.primary)
    }
}
