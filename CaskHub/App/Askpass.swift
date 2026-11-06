//
//  Askpass.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/07/2026.
//

import AppKit

nonisolated struct AskpassDialogRequest: Equatable {
    let token: String?
    let offerRemember: Bool
    let rememberChecked: Bool
}

nonisolated struct AskpassDialogResponse: Equatable {
    let password: String
    let remember: Bool
}

nonisolated enum AskpassOutcome: Equatable {
    case password(String)
    case cancelled
}

nonisolated enum Askpass {
    static func resolve(
        token: String?,
        attempt: Int?,
        store: any AdministratorPasswordStoring,
        presentDialog: (AskpassDialogRequest) -> AskpassDialogResponse?
    ) -> AskpassOutcome {
        let storeAvailable = store.isAvailable
        let passwordSaved = storeAvailable && store.savedPasswordExists()
        var step = AskpassCredentialFlow.firstStep(
            attempt: attempt, storeAvailable: storeAvailable, passwordSaved: passwordSaved
        )
        if step == .touchID {
            step = AskpassCredentialFlow.step(
                after: store.read(reason: touchIDReason(token: token)), storeAvailable: storeAvailable
            )
        }
        switch step {
        case .emit(let password):
            return .password(password)
        case .touchID:
            return .cancelled
        case let .dialog(offerRemember, rememberChecked):
            let request = AskpassDialogRequest(token: token, offerRemember: offerRemember, rememberChecked: rememberChecked)
            guard let response = presentDialog(request) else { return .cancelled }
            switch AskpassCredentialFlow.storeAction(
                remember: response.remember, passwordSaved: passwordSaved, storeAvailable: storeAvailable
            ) {
            case .save: try? store.save(response.password)
            case .delete: store.delete()
            case .none: break
            }
            return .password(response.password)
        }
    }

    static func nextAttempt(marker: URL?) -> Int? {
        guard let marker else { return nil }
        var previous = 0
        if FileManager.default.fileExists(atPath: marker.path) {
            guard let text = try? String(contentsOf: marker, encoding: .utf8),
                  let count = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else { return nil }
            previous = count
        }
        let attempt = previous + 1
        guard (try? Data(String(attempt).utf8).write(to: marker, options: .atomic)) != nil else { return nil }
        return attempt
    }

    @MainActor
    static func runDialog(token: String?, cancellationMarker: URL?, attemptMarker: URL?) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let outcome = resolve(
            token: token,
            attempt: nextAttempt(marker: attemptMarker),
            store: KeychainAdministratorPasswordStore(),
            presentDialog: presentDialog
        )
        guard case .password(let password) = outcome else {
            if let cancellationMarker {
                try? Data().write(to: cancellationMarker, options: .atomic)
            }
            exit(1)
        }
        print(password)
        exit(0)
    }

    private static func touchIDReason(token: String?) -> String {
        token.map { String(localized: "authorize changes for “\($0)”") }
            ?? String(localized: "authorize a Homebrew change")
    }

    @MainActor
    private static func presentDialog(_ request: AskpassDialogRequest) -> AskpassDialogResponse? {
        let app = NSApplication.shared
        let alert = NSAlert()
        alert.messageText = String(localized: "CaskHub needs administrator access")
        alert.informativeText = request.token.map {
            String(localized: "The installer for “\($0)” requires your login password.")
        } ?? String(localized: "This installer requires your login password.")
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 230, height: 24))
        var rememberBox: NSButton?
        if request.offerRemember {
            let box = NSButton(checkboxWithTitle: String(localized: "Use Touch ID next time"), target: nil, action: nil)
            box.state = request.rememberChecked ? .on : .off
            let stack = NSStackView(views: [passwordField, box])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            passwordField.widthAnchor.constraint(equalToConstant: 230).isActive = true
            stack.frame.size = stack.fittingSize
            alert.accessoryView = stack
            rememberBox = box
        } else {
            alert.accessoryView = passwordField
        }
        alert.window.initialFirstResponder = passwordField

        // Activation is cooperative; the floating level keeps the prompt on top.
        alert.window.level = .floating
        app.activate()
        app.requestUserAttention(.criticalRequest)
        guard alert.runModal() == .alertFirstButtonReturn, !passwordField.stringValue.isEmpty else { return nil }
        return AskpassDialogResponse(password: passwordField.stringValue, remember: rememberBox?.state == .on)
    }
}
