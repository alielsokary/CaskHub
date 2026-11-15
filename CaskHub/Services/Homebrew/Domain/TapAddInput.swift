//
//  TapAddInput.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

nonisolated struct TapAddRequest: Equatable, Sendable {
    let tapName: String
    let remoteURL: URL?
    let caskToken: String?

    var brewArguments: [String] {
        ["tap", tapName] + (remoteURL.map { [$0.absoluteString] } ?? [])
    }

    /// Where brew clones the tap: always `Taps/<user>/homebrew-<repo>`, whatever the remote.
    var cloneFolder: String {
        let parts = tapName.split(separator: "/")
        return "…/Taps/\(parts[0])/homebrew-\(parts[1])"
    }
}

/// The pieces a pasted install command loses and gains on its way to the tap command.
nonisolated struct TapCommandRewrite: Equatable, Sendable {
    let keptPrefix: String
    let removedWords: String
    let addedWords: String
    let tapName: String
    let removedSuffix: String
    let caskToken: String

    var finalText: String { "brew tap \(tapName)" }
}

nonisolated enum TapAvailability: Equatable, Sendable {
    case unknown
    case checking
    case available
    case missing
    /// The check itself failed (offline, rate-limited); adding is still allowed and brew reports any error.
    case unreachable
}

nonisolated enum TapAddInputError: Error, Equatable {
    case empty
    case unrecognized
    case officialTap
    /// `http://` or `git://`: anyone on the network could swap the tap's code.
    case insecureRemote
}

/// Turns pasted text into a tap request. Only the parsed names ever reach brew.
nonisolated enum TapAddInput {
    private static let leadingWords: Set = ["brew", "install", "tap"]

    static func parse(_ text: String) -> Result<TapAddRequest, TapAddInputError> {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return .failure(.empty) }
        if words.first == "brew" { words.removeFirst() }
        while let first = words.first, leadingWords.contains(first) { words.removeFirst() }
        words.removeAll { $0.hasPrefix("-") }
        guard words.count == 1, let word = words.first else { return .failure(.unrecognized) }
        let parsed = githubRequest(word).map { .success($0) } ?? remoteRequest(word) ?? nameRequest(word).map { .success($0) }
        guard case let .success(request) = parsed else { return parsed ?? .failure(.unrecognized) }
        return CaskReference.isOfficial(tap: request.tapName) ? .failure(.officialTap) : .success(request)
    }

    static func tapCommandRewrite(for text: String) -> TapCommandRewrite? {
        guard case let .success(request) = parse(text), let token = request.caskToken else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let startsWithBrew = words.first == "brew"
        return TapCommandRewrite(
            keptPrefix: startsWithBrew ? "brew" : "",
            removedWords: startsWithBrew ? words.dropFirst().dropLast().joined(separator: " ") : "",
            addedWords: startsWithBrew ? "tap" : "brew tap",
            tapName: request.tapName,
            removedSuffix: "/\(token)",
            caskToken: token
        )
    }

    private static func githubRequest(_ word: String) -> TapAddRequest? {
        var path = word
        for prefix in ["https://", "http://"] where path.lowercased().hasPrefix(prefix) {
            path.removeFirst(prefix.count)
        }
        guard path.lowercased().hasPrefix("github.com/") else { return nil }
        path.removeFirst("github.com/".count)
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(isValidComponent) else { return nil }
        let user = parts[0].lowercased(), repo = parts[1].lowercased()
        if repo.hasPrefix("homebrew-"), repo.count > "homebrew-".count {
            return TapAddRequest(tapName: "\(user)/\(repo.dropFirst("homebrew-".count))", remoteURL: nil, caskToken: nil)
        }
        return TapAddRequest(
            tapName: "\(user)/\(repo)",
            remoteURL: URL(string: "https://github.com/\(parts[0])/\(parts[1])"),
            caskToken: nil
        )
    }

    /// An https Git URL on any other host, as `brew tap user/repo <URL>` takes it.
    private static func remoteRequest(_ word: String) -> Result<TapAddRequest, TapAddInputError>? {
        guard word.contains("://"), let url = URLComponents(string: word), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "git" { return .failure(.insecureRemote) }
        guard scheme == "https", let host = url.host?.lowercased(), !host.isEmpty, host != "github.com",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return .failure(.unrecognized) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy(isValidComponent) else { return .failure(.unrecognized) }
        var repo = parts[1].lowercased()
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        if repo.hasPrefix("homebrew-"), repo.count > "homebrew-".count { repo.removeFirst("homebrew-".count) }
        guard isValidComponent(repo) else { return .failure(.unrecognized) }
        let port = url.port.map { ":\($0)" } ?? ""
        return .success(TapAddRequest(
            tapName: "\(parts[0].lowercased())/\(repo)",
            remoteURL: URL(string: "https://\(host)\(port)/\(parts[0])/\(parts[1])"),
            caskToken: nil
        ))
    }

    private static func nameRequest(_ word: String) -> TapAddRequest? {
        let parts = word.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (2 ... 3).contains(parts.count), parts.allSatisfy(isValidComponent) else { return nil }
        return TapAddRequest(
            tapName: "\(parts[0])/\(parts[1])".lowercased(),
            remoteURL: nil,
            caskToken: parts.count == 3 ? parts[2].lowercased() : nil
        )
    }

    private static func isValidComponent(_ part: String) -> Bool {
        part.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9_.@+-]*/) != nil
    }
}
