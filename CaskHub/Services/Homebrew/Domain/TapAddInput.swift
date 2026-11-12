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

nonisolated enum TapAddInputError: Error, Equatable {
    case empty
    case unrecognized
    case officialTap
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
        guard let request = githubRequest(word) ?? nameRequest(word) else { return .failure(.unrecognized) }
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
