//
//  HomebrewTapLoader.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

nonisolated struct HomebrewTapLoader: Sendable {
    private static let environment = ["HOMEBREW_NO_AUTO_UPDATE": "1"]

    /// Reads taps without evaluating tap Ruby: only trusted casks go through `brew info`.
    @concurrent
    func load(from brewURL: URL?) async -> TapIndex? {
        guard let brewURL,
              let tapInfo = Self.run(brewURL, ["tap-info", "--json", "--installed"]),
              let taps = Self.taps(in: tapInfo)
        else { return nil }
        let trust = Self.trustOrNone(Self.run(brewURL, ["trust", "--json=v1"]))
        let provisional = TapIndex(taps: taps, casks: [], trust: trust)
        let trustedReferences = taps.flatMap(\.caskTokens).filter(provisional.trusts)
        let trustedCasks = trustedReferences.isEmpty ? [] : Self.run(
            brewURL, ["info", "--cask", "--json=v2"] + trustedReferences
        ).flatMap(Self.infoCasks)
        return Self.makeIndex(taps: taps, trust: trust, trustedCasks: trustedCasks) {
            try? String(contentsOfFile: $0, encoding: .utf8)
        }
    }

    @concurrent
    func installedFormulae(in tap: String, from brewURL: URL?) async -> [String] {
        guard let brewURL, let output = Self.run(brewURL, ["list", "--formula", "--full-name"]) else { return [] }
        return output.split(whereSeparator: \.isNewline).map(String.init).filter { $0.hasPrefix("\(tap)/") }
    }

    @concurrent
    func trust(from brewURL: URL?) async -> TapTrust {
        Self.trustOrNone(brewURL.flatMap { Self.run($0, ["trust", "--json=v1"]) })
    }

    /// Output goes nowhere, so git children outliving a terminated brew can't hold a pipe open.
    // ponytail: fixed 5 min ceiling while holding the exclusive lane; make it cancellable if users hit it.
    @concurrent
    func update(from brewURL: URL?, timeout: TimeInterval = 300) async {
        guard let brewURL else { return }
        let process = Process()
        process.executableURL = brewURL
        process.arguments = ["update"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
    }

    static func taps(in tapInfoJSON: String) -> [TapSummary]? {
        guard let taps = try? decoder.decode([TapSummary].self, from: Data(tapInfoJSON.utf8)) else { return nil }
        return taps.filter { !$0.official && !CaskReference.isOfficial(tap: $0.name) }.sorted { $0.name < $1.name }
    }

    /// Older brew has no `trust` command; then nothing counts as trusted and every first install asks.
    static func trustOrNone(_ output: String?) -> TapTrust {
        output.flatMap(trust(in:)) ?? TapTrust(taps: [], casks: [])
    }

    static func trust(in trustJSON: String) -> TapTrust? {
        try? decoder.decode(TapTrust.self, from: Data(trustJSON.utf8))
    }

    static func makeIndex(
        taps: [TapSummary],
        trust: TapTrust,
        trustedCasks: [Cask]?,
        readFile: (String) -> String?
    ) -> TapIndex {
        let infoByReference = Dictionary((trustedCasks ?? []).map { ($0.reference, $0) }) { first, _ in first }
        let casks = taps.flatMap { tap in
            let files = Dictionary(tap.caskFiles.map { (fileToken($0), $0) }) { first, _ in first }
            return tap.caskTokens.map { reference in
                if let info = infoByReference[reference] { return info }
                let token = CaskReference.bareToken(reference)
                let source = files[token].flatMap(readFile) ?? ""
                return CaskFileTextParser.cask(fromSource: source, token: token, tap: tap.name)
            }
        }
        return TapIndex(taps: taps, casks: casks.sorted { $0.reference < $1.reference }, trust: trust)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func infoCasks(_ output: String) -> [Cask]? {
        struct Output: Decodable { let casks: [Cask] }
        return (try? decoder.decode(Output.self, from: Data(output.utf8)))?.casks.map {
            var cask = $0
            cask.provenance = .tapInfo
            return cask
        }
    }

    private static func fileToken(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private static func run(_ brewURL: URL, _ arguments: [String]) -> String? {
        guard let result = ProcessCapture.capture(brewURL, arguments: arguments, environment: environment),
              result.status == 0
        else { return nil }
        return result.output
    }
}
