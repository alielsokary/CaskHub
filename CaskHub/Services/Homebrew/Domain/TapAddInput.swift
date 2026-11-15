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

    private var nameParts: (user: Substring, repo: Substring) {
        let parts = tapName.split(separator: "/")
        return (parts[0], parts[1])
    }

    /// Where brew clones the tap: always `Taps/<user>/homebrew-<repo>`, whatever the remote.
    var cloneFolder: String {
        "…/Taps/\(nameParts.user)/homebrew-\(nameParts.repo)"
    }

    /// The custom remote, else the GitHub repository brew derives from the name.
    var repositoryURL: URL {
        remoteURL ?? URL(string: "https://github.com/\(nameParts.user)/homebrew-\(nameParts.repo)")!
    }

    /// `host/path` of the repository, so a familiar tap name can't hide where the code comes from.
    var sourceText: String {
        (repositoryURL.host() ?? "") + repositoryURL.path()
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

    /// A `brew tap` remote CaskHub accepts: https with a host, and no credentials, query, or fragment.
    static func secureRemote(_ text: String) -> URL? {
        guard let url = URLComponents(string: text), url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return nil }
        return url.url
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
        let repo = tapRepoName(parts[1])
        // brew finds github.com/user/homebrew-repo by itself; any other repository needs its URL.
        let remote = parts[1].lowercased() == "homebrew-\(repo)" ? nil : URL(string: "https://github.com/\(parts[0])/\(parts[1])")
        return TapAddRequest(tapName: "\(parts[0].lowercased())/\(repo)", remoteURL: remote, caskToken: nil)
    }

    /// An https Git URL on any other host, as `brew tap user/repo <URL>` takes it.
    private static func remoteRequest(_ word: String) -> Result<TapAddRequest, TapAddInputError>? {
        guard word.contains("://"), let scheme = URLComponents(string: word)?.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "git" { return .failure(.insecureRemote) }
        guard let url = secureRemote(word), let host = url.host()?.lowercased(), host != "github.com" else {
            return .failure(.unrecognized)
        }
        let parts = url.path().split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy(isValidComponent) else { return .failure(.unrecognized) }
        let repo = tapRepoName(parts[1])
        guard isValidComponent(repo) else { return .failure(.unrecognized) }
        let port = url.port.map { ":\($0)" } ?? ""
        return .success(TapAddRequest(
            tapName: "\(parts[0].lowercased())/\(repo)",
            remoteURL: URL(string: "https://\(host)\(port)/\(parts[0])/\(parts[1])"),
            caskToken: nil
        ))
    }

    /// `homebrew-tools.git` names the tap `tools`, as brew does.
    private static func tapRepoName(_ repository: String) -> String {
        var repo = repository.lowercased()
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        if repo.hasPrefix("homebrew-"), repo.count > "homebrew-".count { repo.removeFirst("homebrew-".count) }
        return repo
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
