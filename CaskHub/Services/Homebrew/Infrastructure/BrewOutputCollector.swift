//
//  BrewOutputCollector.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/07/2026.
//

import Foundation

/// Collects a child process's merged output without ever blocking on the pipe.
/// Resolves on EOF — or shortly after exit when a grandchild inherited the pipe's
/// write end and kept it open (brew's helpers do this), which would otherwise
/// leave the UI spinning forever.
nonisolated final class BrewOutputCollector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.caskhub.brew-output")
    private var tail = ""
    private var sawEOF = false
    private var exited = false
    private var finished = false
    private var continuation: CheckedContinuation<String, Never>?

    /// Must be called before `process.run()` so a fast-exiting process can't
    /// slip past the termination handler.
    func attach(
        to process: Process,
        readHandle handle: FileHandle,
        onChunk: @escaping @Sendable (String) -> Void
    ) {
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            self?.queue.async {
                guard let self else { return }
                if data.isEmpty {
                    self.sawEOF = true
                    if self.exited { self.finish() }
                } else if let text = String(data: data, encoding: .utf8) {
                    let plainText = Self.plainText(text)
                    self.tail = String((self.tail + plainText).suffix(2000))
                    if !plainText.isEmpty {
                        onChunk(plainText)
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            queue.async {
                self.exited = true
                if self.sawEOF {
                    self.finish()
                } else {
                    // Grace period for trailing output, then stop waiting on the pipe.
                    self.queue.asyncAfter(deadline: .now() + 2) { self.finish() }
                }
            }
        }
    }

    /// The process is guaranteed to have exited by the time this returns.
    func output() async -> String {
        await withCheckedContinuation { newContinuation in
            queue.async {
                if self.finished {
                    newContinuation.resume(returning: self.tail)
                } else {
                    self.continuation = newContinuation
                }
            }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: tail)
        continuation = nil
    }

    private static let ansiEscapes = try? NSRegularExpression(
        pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]"
    )

    private static func plainText(_ text: String) -> String {
        let stripped: String
        if let ansiEscapes {
            stripped = ansiEscapes.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        } else {
            stripped = text
        }
        return stripped.replacingOccurrences(of: "\r", with: "\n")
    }
}
