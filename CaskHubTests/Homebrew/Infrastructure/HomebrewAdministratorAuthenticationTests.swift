@testable import CaskHub
import XCTest

final class HomebrewAdministratorAuthenticationTests: XCTestCase {
    @MainActor
    func test_mutations_have_a_controlling_terminal_without_requesting_authorization_upfront() async throws {
        for command in ["install", "upgrade", "reinstall", "uninstall"] {
            let arguments = [command, "--cask", "a token's $(printf injected); value"]
            let fixture = try await runFixture(arguments: arguments)

            XCTAssertEqual(fixture.result.exitCode, 0)
            XCTAssertTrue(fixture.result.output.contains("controlling-terminal:true\n"))
            XCTAssertTrue(fixture.result.output.contains("askpass:\n"))
            XCTAssertFalse(fixture.result.output.contains("checked:1"))
            XCTAssertNil(fixture.askpassLog)
            XCTAssertFalse(fixture.cancelled)
            for argument in arguments {
                XCTAssertTrue(fixture.result.output.contains("argument:\(argument)\n"))
            }
        }
    }

    @MainActor
    func test_unavailable_touch_id_keeps_the_existing_password_helper() async throws {
        let fixture = try await runFixture(canUseTouchID: false, body: "\"$SUDO_ASKPASS\" >/dev/null")

        XCTAssertEqual(fixture.result.exitCode, 0)
        XCTAssertEqual(fixture.askpassLog, "password-dialog\n")
        XCTAssertTrue(fixture.result.output.contains("controlling-terminal:false\n"))
        XCTAssertFalse(fixture.cancelled)
    }

    @MainActor
    func test_read_only_and_noninteractive_operations_keep_the_original_transport() async throws {
        for arguments in [
            ["fetch", "--cask", "example"], ["info", "example"], [],
            ["upgrade", "--dry-run"], ["install", "--help"]
        ] {
            let fixture = try await runFixture(arguments: arguments)
            XCTAssertEqual(fixture.result.exitCode, 0)
            XCTAssertTrue(fixture.result.output.contains("controlling-terminal:false\n"))
            XCTAssertNil(fixture.askpassLog)
            XCTAssertFalse(fixture.cancelled)
        }
    }

    @MainActor
    func test_missing_askpass_and_explicit_no_sudo_are_respected() async throws {
        for overrides: [String: String?] in [
            ["SUDO_ASKPASS": nil], ["SUDO_ASKPASS": ""], ["HOMEBREW_NO_SUDO": "1"],
            ["HOMEBREW_SUDO_THROUGH_SUDO_USER": "1"]
        ] {
            let fixture = try await runFixture(overrides: overrides)
            XCTAssertEqual(fixture.result.exitCode, 0)
            XCTAssertTrue(fixture.result.output.contains("controlling-terminal:false\n"))
            XCTAssertFalse(fixture.cancelled)
        }
    }

    @MainActor
    func test_native_authorization_cancellation_stops_even_an_optional_followup_action() async throws {
        let fixture = try await runFixture(body: """
        trap 'printf "interrupted-cleanup\\n"; exit 130' INT
        stty -echo </dev/tty
        read -r password </dev/tty || true
        printf 'unexpected-followup-action\\n'
        """)

        XCTAssertEqual(fixture.result.exitCode, 130)
        XCTAssertTrue(fixture.cancelled)
        XCTAssertTrue(fixture.result.output.contains("interrupted-cleanup"))
        XCTAssertFalse(fixture.result.output.contains("unexpected-followup-action"))
        XCTAssertTrue(fixture.delivered.contains("interrupted-cleanup"))
        XCTAssertFalse(fixture.delivered.contains("unexpected-followup-action"))
        XCTAssertNil(fixture.askpassLog)
    }

    @MainActor
    func test_terminal_transport_preserves_brew_failure_and_diagnostics() async throws {
        let fixture = try await runFixture(body: "printf 'brew failure\\n' >&2; exit 42")

        XCTAssertEqual(fixture.result.exitCode, 42)
        XCTAssertFalse(fixture.result.wasTerminatedBySignal)
        XCTAssertTrue(fixture.result.output.contains("brew failure\n"))
        XCTAssertFalse(fixture.cancelled)
    }

    @MainActor
    func test_default_availability_probe_does_not_authorize_an_unprivileged_operation() async throws {
        let fixture = try await runFixture(useDefaultAvailability: true)

        XCTAssertEqual(fixture.result.exitCode, 0)
        XCTAssertNil(fixture.askpassLog)
        XCTAssertFalse(fixture.cancelled)
    }

    @MainActor
    func test_configuration_requires_an_active_sufficient_auth_rule() {
        for rule in ["auth sufficient pam_tid.so", "auth sufficient /usr/lib/pam/pam_tid.so # enabled"] {
            XCTAssertTrue(HomebrewAdministratorAuthentication.touchIDIsConfigured { $0 == "sudo" ? rule : nil })
        }
        for rule in ["# auth sufficient pam_tid.so", "account sufficient pam_tid.so", "auth required pam_tid.so", ""] {
            XCTAssertFalse(HomebrewAdministratorAuthentication.touchIDIsConfigured { $0 == "sudo" ? rule : nil })
        }
    }

    @MainActor
    func test_configuration_follows_auth_includes_and_handles_missing_files_and_cycles() {
        let configurations = ["sudo": "auth include sudo_local", "sudo_local": "auth sufficient pam_tid.so"]
        XCTAssertTrue(HomebrewAdministratorAuthentication.touchIDIsConfigured { configurations[$0] })
        XCTAssertFalse(HomebrewAdministratorAuthentication.touchIDIsConfigured { _ in nil })
        XCTAssertFalse(HomebrewAdministratorAuthentication.touchIDIsConfigured { _ in "auth include sudo" })
        XCTAssertFalse(HomebrewAdministratorAuthentication.touchIDIsConfigured {
            $0 == "sudo" ? "auth include sudo_local" : "# auth sufficient pam_tid.so"
        })
    }

    private struct Fixture {
        let result: BrewProcessResult
        let delivered: String
        let askpassLog: String?
        let cancelled: Bool
    }

    private struct Executables {
        let brew: URL
        let askpass: URL
        let log: URL
    }

    @MainActor
    private func runFixture(
        arguments: [String] = ["install", "--cask", "example"],
        canUseTouchID: Bool = true,
        useDefaultAvailability: Bool = false,
        overrides: [String: String?] = [:],
        body: String = ""
    ) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("caskhub auth \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executables = try makeExecutables(in: directory, body: body)
        var environment = ProcessInfo.processInfo.environment
        environment["SUDO_ASKPASS"] = executables.askpass.path
        environment["AUTH_TEST_LOG"] = executables.log.path
        environment["HOMEBREW_NO_SUDO"] = nil
        environment["HOMEBREW_SUDO_THROUGH_SUDO_USER"] = nil
        environment["HOMEBREW_SUDO_CHECKED"] = nil
        for (key, value) in overrides { environment[key] = value }
        let runner = useDefaultAvailability ? SystemBrewProcessRunner() : SystemBrewProcessRunner(
            canUseTouchID: { canUseTouchID }
        )
        var delivered = ""
        let result = try await runner.run(
            executableURL: executables.brew,
            arguments: arguments,
            environment: environment,
            onStart: { _ in },
            onChunk: { delivered += $0 }
        )
        return Fixture(
            result: result,
            delivered: delivered,
            askpassLog: try? String(contentsOf: executables.log, encoding: .utf8),
            cancelled: FileManager.default.fileExists(
                atPath: AskpassScriptManager.cancellationMarker(for: executables.askpass).path
            )
        )
    }

    private func makeExecutables(in directory: URL, body: String) throws -> Executables {
        let brew = directory.appendingPathComponent("brew's fixture")
        let askpass = directory.appendingPathComponent("askpass's fixture")
        let log = directory.appendingPathComponent("askpass.log")
        try """
        #!/bin/sh
        printf 'password-dialog\\n' > "$AUTH_TEST_LOG"
        """.write(to: askpass, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        if read -r value; then exit 99; fi
        if ( : >/dev/tty ) 2>/dev/null; then
            printf 'controlling-terminal:true\\n'
        else
            printf 'controlling-terminal:false\\n'
        fi
        printf 'askpass:%s\\n' "$SUDO_ASKPASS"
        printf 'checked:%s\\n' "$HOMEBREW_SUDO_CHECKED"
        for argument in "$@"; do printf 'argument:%s\\n' "$argument"; done
        \(body)
        """.write(to: brew, atomically: true, encoding: .utf8)
        for executable in [brew, askpass] {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        return Executables(brew: brew, askpass: askpass, log: log)
    }
}
