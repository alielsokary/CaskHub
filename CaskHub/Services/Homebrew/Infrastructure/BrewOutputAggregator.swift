//
//  BrewOutputAggregator.swift
//  CaskHub
//
//  Created by Ali Elsokary on 03/08/2026.
//

import Foundation

/// Parses brew's pty output off the MainActor; main receives updates at ~10/s.
nonisolated final class BrewOutputAggregator: @unchecked Sendable {
    struct Parsed: Sendable {
        let update: BrewProgressParser.Update
        let cachedDownloadBytes: Int64?
    }

    private let queue = DispatchQueue(label: "com.caskhub.brew-parse", qos: .userInitiated)
    private let fileManager: FileManager
    private var buffers: [String: String] = [:]
    private var lastParses: [String: Date] = [:]

    private static let phaseMarkers = ["==>", "Verifying", "Already downloaded:"]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ingest(
        _ output: String,
        token: String,
        deliver: @escaping @MainActor @Sendable (Parsed) -> Void
    ) {
        queue.async { [self] in
            let buffered = String(((buffers[token] ?? "") + output).suffix(6_000))
            buffers[token] = buffered

            // Skipped chunks stay buffered, so the next parse sees their state.
            let hasPhaseMarker = Self.phaseMarkers.contains(where: output.contains)
            if !hasPhaseMarker,
               let lastParse = lastParses[token],
               Date.now.timeIntervalSince(lastParse) < 0.10 {
                return
            }

            let update = BrewProgressParser.parse(buffered)
            // Marker parses must never throttle the byte line after them.
            if update.byteProgress != nil {
                lastParses[token] = Date.now
            }
            let parsed = Parsed(
                update: update,
                cachedDownloadBytes: cachedDownloadBytes(for: update)
            )
            Task { @MainActor in deliver(parsed) }
        }
    }

    func clear(token: String) {
        queue.async { [self] in
            buffers[token] = nil
            lastParses[token] = nil
        }
    }

    /// Resolves after all previously enqueued deliveries land on the MainActor.
    func drain() async {
        await withCheckedContinuation { continuation in
            queue.async {
                Task { @MainActor in continuation.resume() }
            }
        }
    }

    private func cachedDownloadBytes(for update: BrewProgressParser.Update) -> Int64? {
        guard update.phase == .usingCachedDownload,
              let path = update.cachedDownloadPath,
              let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 0
        else { return nil }
        return size.int64Value
    }
}
