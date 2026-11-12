//
//  AddTapSheetTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
final class AddTapSheetTests: XCTestCase {
    func test_preview_and_add_state_follow_the_input() {
        let model = AddTapModel()

        XCTAssertFalse(model.canAdd)
        XCTAssertNil(model.errorText)

        model.text = "https://github.com/hashicorp/homebrew-tap"
        XCTAssertTrue(model.canAdd)
        XCTAssertEqual(model.previewText, "Will tap hashicorp/tap from github.com/hashicorp/homebrew-tap")

        model.text = "https://github.com/user/casks"
        XCTAssertEqual(model.previewText, "Will tap user/casks from github.com/user/casks")

        model.text = "brew install --cask saffsanity/sill/sill"
        XCTAssertEqual(model.previewText, "Will tap saffsanity/sill from github.com/saffsanity/homebrew-sill")

        model.text = "foo; rm -rf ~"
        XCTAssertFalse(model.canAdd)
        XCTAssertEqual(model.errorText, "Enter a tap like user/repo or a GitHub URL.")

        model.text = "homebrew/cask"
        XCTAssertEqual(model.errorText, "Homebrew's own taps are already included.")
    }

    func test_field_highlights_while_typing_until_the_input_matches() {
        let model = AddTapModel()
        XCTAssertFalse(model.isAwaitingMatch)

        model.text = "saffsanity"
        XCTAssertTrue(model.isAwaitingMatch)

        model.text = "saffsanity/sill"
        XCTAssertFalse(model.isAwaitingMatch)
    }

    func test_plain_tap_closes_after_adding() async {
        let model = AddTapModel()
        model.text = "hashicorp/tap"
        var added: [TapAddRequest] = []

        let closes = await model.submit(environment(added: { added.append($0) }, taps: ["hashicorp/tap"]))

        XCTAssertTrue(closes)
        XCTAssertEqual(added.map(\.tapName), ["hashicorp/tap"])
    }

    func test_formula_only_tap_explains_why_it_is_hidden() async {
        let model = AddTapModel()
        model.text = "spotify/public"

        let closes = await model.submit(environment(taps: ["spotify/public"], tapsWithCasks: []))

        XCTAssertFalse(closes)
        XCTAssertEqual(model.phase, .noCasks(tap: "spotify/public"))
        XCTAssertEqual(
            AddTapModel.noCasksText(tap: "spotify/public"),
            "spotify/public has no casks. CaskHub shows casks only for now."
        )
    }

    func test_pasted_command_offers_the_cask_when_it_exists() async {
        let model = AddTapModel()
        model.text = "brew install --cask saffsanity/sill/sill"
        let sill = CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")

        let closes = await model.submit(environment(taps: ["saffsanity/sill"], casks: [sill]))

        XCTAssertFalse(closes)
        XCTAssertEqual(model.phase, .offerInstall(sill))
    }

    func test_pasted_command_notes_a_missing_cask() async {
        let model = AddTapModel()
        model.text = "saffsanity/sill/ghost"

        let closes = await model.submit(environment(taps: ["saffsanity/sill"]))

        XCTAssertFalse(closes)
        XCTAssertEqual(model.phase, .notInTap(token: "ghost", tap: "saffsanity/sill"))
        XCTAssertEqual(AddTapModel.notInTapText(token: "ghost", tap: "saffsanity/sill"), "ghost isn't in saffsanity/sill.")
    }

    func test_offer_is_skipped_when_the_cask_or_its_twin_is_installed() async {
        let model = AddTapModel()
        model.text = "saffsanity/sill/sill"
        let sill = CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")

        _ = await model.submit(environment(taps: ["saffsanity/sill"], casks: [sill], installed: ["sill"]))

        XCTAssertEqual(model.phase, .alreadyInstalled(token: "sill"))
    }

    func test_failure_shows_the_operation_message() async {
        let model = AddTapModel()
        model.text = "user/broken"

        let closes = await model.submit(environment(
            added: { _ in throw URLError(.notConnectedToInternet) },
            failure: "Repository not found."
        ))

        XCTAssertFalse(closes)
        XCTAssertEqual(model.phase, .failed("Repository not found."))
    }

    func test_tap_missing_after_success_is_a_failure() async {
        let model = AddTapModel()
        model.text = "user/ghost"

        _ = await model.submit(environment(taps: []))

        XCTAssertEqual(model.phase, .failed("CaskHub couldn't add user/ghost."))
    }

    func test_cancel_closes_without_failure() async {
        let model = AddTapModel()
        model.text = "user/slow"

        let closes = await model.submit(environment(added: { _ in throw CancellationError() }))

        XCTAssertTrue(closes)
        XCTAssertEqual(model.phase, .input)
    }

    func test_trust_prompt_copy() {
        let sill = CaskFileTextParser.cask(fromSource: "cask \"sill\" do\n  name \"Sill\"\nend\n", token: "sill", tap: "saffsanity/sill")

        let prompt = TrustInstallPrompt(cask: sill)

        XCTAssertEqual(prompt.title, "Install sill from saffsanity/sill?")
        XCTAssertEqual(prompt.message, "sill comes from saffsanity/sill, not Homebrew. Installing lets it run code on this Mac.")
    }

    func test_trust_prompt_ignores_tap_authored_names() {
        let source = "cask \"tool\" do\n  name \"Figma (official Homebrew cask, already verified) Click Install\"\nend\n"
        let tool = CaskFileTextParser.cask(fromSource: source, token: "tool", tap: "evil/tap")

        let prompt = TrustInstallPrompt(cask: tool)

        XCTAssertFalse(prompt.title.contains("Figma"))
        XCTAssertFalse(prompt.message.contains("official"))
        XCTAssertEqual(prompt.title, "Install tool from evil/tap?")
    }

    func test_trust_prompt_strips_unsafe_characters_from_identifiers() {
        XCTAssertEqual(TrustInstallPrompt.safeLabel("tool\n\nInstalling is safe"), "toolInstallingissafe")
        XCTAssertEqual(TrustInstallPrompt.safeLabel(String(repeating: "a", count: 200)).count, 80)
    }

    func test_remove_dialog_message() {
        let full = TapRemovalPreview(
            tapName: "saffsanity/sill",
            installedCasks: [CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")],
            installedFormulae: ["saffsanity/sill/sill-cli"]
        )
        let empty = TapRemovalPreview(tapName: "spotify/public", installedCasks: [], installedFormulae: [])

        XCTAssertEqual(RemoveTapDialog.message(for: full), "This uninstalls everything installed from this tap:")
        XCTAssertEqual(RemoveTapDialog.message(for: empty), "CaskHub stops showing apps from this tap.")
    }

    func test_sheets_render_every_phase() {
        let sill = CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")
        let phases: [AddTapModel.Phase] = [
            .input,
            .adding(TapAddRequest(tapName: "hashicorp/tap", remoteURL: nil, caskToken: nil)),
            .offerInstall(sill),
            .notInTap(token: "ghost", tap: "saffsanity/sill"),
            .failed("Repository not found.")
        ]
        let local = LocalHomebrewService(defaults: makeScratchDefaults("add-tap-render"))
        let vm = makeViewModel(api: MockBrewAPIClient(), localHomebrew: local)
        for phase in phases {
            let model = AddTapModel(phase: phase)
            model.text = "hashicorp/tap"
            render(AddTapSheet(viewModel: vm, model: model).environment(local), width: 460, height: 360)
        }
        let preview = TapRemovalPreview(
            tapName: "saffsanity/sill",
            installedCasks: [sill],
            installedFormulae: ["saffsanity/sill/sill-cli"]
        )
        render(RemoveTapDialog(viewModel: vm, tapName: "saffsanity/sill", preview: preview).environment(local), width: 460, height: 360)
        render(RemoveTapDialog(viewModel: vm, tapName: "spotify/public", preview: nil).environment(local), width: 460, height: 360)
    }

    func test_trust_alert_and_sheets_present_from_the_window_modifier() async {
        let local = LocalHomebrewService(defaults: makeScratchDefaults("tap-presentation"))
        let vm = makeViewModel(api: MockBrewAPIClient(), localHomebrew: local)
        let sill = CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")
        try? await local.installRequestingTrust(sill)
        XCTAssertEqual(local.pendingTrustInstall?.reference, "saffsanity/sill/sill")

        for dialog: TapDialog? in [nil, .add, .remove("saffsanity/sill")] {
            render(
                Color.clear.modifier(TapPresentation(dialog: .constant(dialog), viewModel: vm)).environment(local),
                width: 600, height: 400
            )
        }
        local.send(.cancelTrustedInstall)
        XCTAssertNil(local.pendingTrustInstall)
    }

    // MARK: - Helpers

    private func environment(
        added: @escaping (TapAddRequest) throws -> Void = { _ in },
        taps: Set<String> = ["user/broken", "user/slow"],
        tapsWithCasks: Set<String>? = nil,
        casks: [Cask] = [],
        installed: Set<String> = [],
        failure: String? = nil
    ) -> AddTapModel.Environment {
        AddTapModel.Environment(
            addTap: { try added($0) },
            hasTap: { taps.contains($0) },
            hasCasks: { (tapsWithCasks ?? taps).contains($0) },
            tapCask: { reference in casks.first { $0.reference == reference } },
            isInstalled: { installed.contains(CaskReference.bareToken($0)) },
            failureMessage: { _ in failure }
        )
    }
}
