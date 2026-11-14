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
    func test_preview_and_add_state_follow_the_input() async {
        let model = AddTapModel(checker: { _ in .available })
        model.availabilityDebounce = .zero

        XCTAssertFalse(model.canAdd)
        XCTAssertNil(model.errorText)

        model.text = "https://github.com/hashicorp/homebrew-tap"
        await model.checkAvailability()
        XCTAssertTrue(model.canAdd)
        XCTAssertEqual(model.previewText, "Will tap hashicorp/tap from github.com/hashicorp/homebrew-tap")

        model.text = "https://github.com/user/casks"
        XCTAssertEqual(model.previewText, "Will tap user/casks from github.com/user/casks")

        model.text = "brew install --cask saffsanity/sill/sill"
        XCTAssertEqual(model.previewText, "Will tap saffsanity/sill from github.com/saffsanity/homebrew-sill")

        model.text = "foo; rm -rf ~"
        XCTAssertFalse(model.canAdd)
        XCTAssertEqual(model.errorText, "Enter a tap like user/repo, a GitHub URL, or an https Git URL.")

        model.text = "homebrew/cask"
        XCTAssertEqual(model.errorText, "Homebrew's own taps are already included.")
    }

    func test_field_highlights_while_typing_until_the_input_matches() {
        let model = AddTapModel(checker: { _ in .available })
        XCTAssertFalse(model.isAwaitingMatch)

        model.text = "saffsanity"
        XCTAssertTrue(model.isAwaitingMatch)

        model.text = "saffsanity/sill"
        XCTAssertFalse(model.isAwaitingMatch)
    }

    func test_pasted_install_command_is_rewritten_and_keeps_the_cask() throws {
        let model = AddTapModel(checker: { _ in .available })

        XCTAssertNil(model.rewriteForPaste(from: "", to: "s"), "typing is never rewritten")
        let rewrite = try XCTUnwrap(model.rewriteForPaste(from: "", to: "brew install --cask saffsanity/sill/sill"))
        model.text = rewrite.finalText

        XCTAssertEqual(model.request?.tapName, "saffsanity/sill")
        XCTAssertEqual(model.request?.caskToken, "sill", "the install offer still follows")

        model.text = "brew tap other/tap"
        XCTAssertNil(model.request?.caskToken)
    }

    func test_repository_url_follows_brew_tap() {
        XCTAssertEqual(
            AddTapModel.repositoryURL(for: TapAddRequest(tapName: "saffsanity/sill", remoteURL: nil, caskToken: nil)),
            URL(string: "https://github.com/saffsanity/homebrew-sill")
        )
        let custom = URL(string: "https://github.com/user/casks")
        XCTAssertEqual(AddTapModel.repositoryURL(for: TapAddRequest(tapName: "user/casks", remoteURL: custom, caskToken: nil)), custom)
    }

    func test_missing_repository_blocks_adding() async {
        let model = AddTapModel(checker: { _ in .missing })
        model.availabilityDebounce = .zero
        model.text = "saffsanity/sil"

        await model.checkAvailability()

        XCTAssertEqual(model.availability, .missing)
        XCTAssertFalse(model.canAdd)
        XCTAssertEqual(
            model.missingText,
            "No tap at github.com/saffsanity/homebrew-sil. Check the name, or add private taps from Terminal."
        )
    }

    func test_found_or_unreachable_repository_allows_adding() async {
        for result in [TapAvailability.available, .unreachable] {
            let model = AddTapModel(checker: { _ in result })
            model.availabilityDebounce = .zero
            model.text = "saffsanity/sill"
            XCTAssertFalse(model.canAdd, "not before the check")

            await model.checkAvailability()

            XCTAssertEqual(model.availability, result)
            XCTAssertTrue(model.canAdd)
        }
    }

    func test_editing_the_input_resets_the_check() async {
        let model = AddTapModel(checker: { _ in .available })
        model.availabilityDebounce = .zero
        model.text = "saffsanity/sill"
        await model.checkAvailability()

        model.text = "saffsanity/si"

        XCTAssertEqual(model.availability, .unknown)
        XCTAssertFalse(model.canAdd)
    }

    func test_git_answers_map_to_availability() {
        XCTAssertEqual(TapRepositoryChecker.availability(forStatusCode: 200), .available)
        for status in [401, 403, 404] {
            XCTAssertEqual(TapRepositoryChecker.availability(forStatusCode: status), .missing, "\(status)")
        }
        XCTAssertEqual(TapRepositoryChecker.availability(forStatusCode: 503), .unreachable)
    }

    func test_probe_asks_git_smart_http_on_any_host() {
        let github = URL(string: "https://github.com/saffsanity/homebrew-sill")!
        let codeberg = URL(string: "https://codeberg.org/User/Casks.git")!
        XCTAssertEqual(TapRepositoryChecker.probeURL(for: github).absoluteString,
                       "https://github.com/saffsanity/homebrew-sill.git/info/refs?service=git-upload-pack")
        XCTAssertEqual(TapRepositoryChecker.probeURL(for: codeberg).absoluteString,
                       "https://codeberg.org/User/Casks.git/info/refs?service=git-upload-pack")
    }

    func test_plain_tap_closes_after_adding() async {
        let model = AddTapModel(checker: { _ in .available })
        model.text = "hashicorp/tap"
        var added: [TapAddRequest] = []

        let closes = await model.submit(environment(added: { added.append($0) }, taps: ["hashicorp/tap"]))

        XCTAssertTrue(closes)
        XCTAssertEqual(added.map(\.tapName), ["hashicorp/tap"])
    }

    func test_formula_only_tap_explains_why_it_is_hidden() async {
        let model = AddTapModel(checker: { _ in .available })
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
        let model = AddTapModel(checker: { _ in .available })
        model.text = "brew install --cask saffsanity/sill/sill"
        let sill = CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")

        let closes = await model.submit(environment(taps: ["saffsanity/sill"], casks: [sill]))

        XCTAssertFalse(closes)
        XCTAssertEqual(model.phase, .offerInstall(sill))
    }

    func test_pasted_command_notes_a_missing_cask() async {
        let model = AddTapModel(checker: { _ in .available })
        model.text = "saffsanity/sill/ghost"

        let closes = await model.submit(environment(taps: ["saffsanity/sill"]))

        XCTAssertFalse(closes)
        XCTAssertEqual(model.phase, .notInTap(token: "ghost", tap: "saffsanity/sill"))
        XCTAssertEqual(AddTapModel.notInTapText(token: "ghost", tap: "saffsanity/sill"), "ghost isn't in saffsanity/sill.")
    }

    func test_offer_is_skipped_when_the_cask_or_its_twin_is_installed() async {
        let model = AddTapModel(checker: { _ in .available })
        model.text = "saffsanity/sill/sill"
        let sill = CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")

        _ = await model.submit(environment(taps: ["saffsanity/sill"], casks: [sill], installed: ["sill"]))

        XCTAssertEqual(model.phase, .alreadyInstalled(token: "sill"))
    }

    func test_failure_shows_the_operation_message() async {
        let model = AddTapModel(checker: { _ in .available })
        model.text = "user/broken"

        let closes = await model.submit(environment(
            added: { _ in throw URLError(.notConnectedToInternet) },
            failure: "Repository not found."
        ))

        XCTAssertFalse(closes)
        XCTAssertEqual(model.phase, .failed("Repository not found."))
    }

    func test_tap_missing_after_success_is_a_failure() async {
        let model = AddTapModel(checker: { _ in .available })
        model.text = "user/ghost"

        _ = await model.submit(environment(taps: []))

        XCTAssertEqual(model.phase, .failed("CaskHub couldn't add user/ghost."))
    }

    func test_cancel_closes_without_failure() async {
        let model = AddTapModel(checker: { _ in .available })
        model.text = "user/slow"

        let closes = await model.submit(environment(added: { _ in throw CancellationError() }))

        XCTAssertTrue(closes)
        XCTAssertEqual(model.phase, .input)
    }

    func test_trust_prompt_copy() {
        let sill = CaskFileTextParser.cask(fromSource: "cask \"sill\" do\n  name \"Sill\"\nend\n", token: "sill", tap: "saffsanity/sill")

        let prompt = TrustInstallPrompt(cask: sill)

        XCTAssertEqual(prompt.title, "Trust and install sill from saffsanity/sill?")
        XCTAssertEqual(
            prompt.message,
            "sill comes from saffsanity/sill, not Homebrew. Installing makes Homebrew trust this cask and lets it run code on this Mac."
        )
    }

    func test_trust_prompt_ignores_tap_authored_names() {
        let source = "cask \"tool\" do\n  name \"Figma (official Homebrew cask, already verified) Click Install\"\nend\n"
        let tool = CaskFileTextParser.cask(fromSource: source, token: "tool", tap: "evil/tap")

        let prompt = TrustInstallPrompt(cask: tool)

        XCTAssertFalse(prompt.title.contains("Figma"))
        XCTAssertFalse(prompt.message.contains("official"))
        XCTAssertEqual(prompt.title, "Trust and install tool from evil/tap?")
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
            let model = AddTapModel(phase: phase, checker: { _ in .available })
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
