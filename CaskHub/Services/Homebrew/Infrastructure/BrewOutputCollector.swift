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
    private var pendingUTF8 = Data()
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
                    if self.exited { self.finish(onChunk: onChunk) }
                } else {
                    let plainText = self.appendOutput(self.decode(data))
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
                    self.finish(onChunk: onChunk)
                } else {
                    // Grace period for trailing output, then stop waiting on the pipe.
                    self.queue.asyncAfter(deadline: .now() + 2) { self.finish(onChunk: onChunk) }
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

    private func finish(onChunk: @Sendable (String) -> Void) {
        guard !finished else { return }
        // Replace an incomplete final scalar without dropping any preceding diagnostic.
        // swiftlint:disable:next optional_data_string_conversion
        let remainder = appendOutput(String(decoding: pendingUTF8, as: UTF8.self))
        pendingUTF8.removeAll()
        if !remainder.isEmpty { onChunk(remainder) }
        finished = true
        continuation?.resume(returning: tail)
        continuation = nil
    }

    private func decode(_ data: Data) -> String {
        pendingUTF8.append(data)
        var end = pendingUTF8.endIndex
        // Keep at most three bytes when a Unicode scalar straddles reads.
        if let start = pendingUTF8.indices.suffix(3).last(where: { pendingUTF8[$0] & 0xC0 != 0x80 }) {
            let length = switch pendingUTF8[start] {
            case 0xC2 ... 0xDF: 2
            case 0xE0 ... 0xEF: 3
            case 0xF0 ... 0xF4: 4
            default: 1
            }
            if pendingUTF8.distance(from: start, to: end) < length { end = start }
        }
        // Malformed output must not discard the rest of a read's error text.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: pendingUTF8[..<end], as: UTF8.self)
        pendingUTF8.removeSubrange(..<end)
        return text
    }

    private func appendOutput(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let plainText = Self.plainText(text)
        // Strip before capping, or progress frames evict the error line.
        tail = String(HomebrewOutputDiagnostics.stripProgressNoise(from: tail + plainText).suffix(2000))
        return plainText
    }

    private static let ansiEscapes = try? NSRegularExpression(
        pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]"
    )

    static func plainText(_ text: String) -> String {
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
        // The pty's ONLCR emits \r\n; fold it first or every line doubles.
        return stripped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
