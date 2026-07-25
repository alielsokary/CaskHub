#!/usr/bin/env swift

import Foundation

struct Frame {
    let name: String
    let binary: String
    let path: String
    let sourcePath: String
}

struct Aggregate {
    var inclusiveWeight = 0.0
    var selfWeight = 0.0
    var sampleCount = 0
}

enum TraceAnalysisError: Error, CustomStringConvertible {
    case invalidDocument(String)
    case usage

    var description: String {
        switch self {
        case let .invalidDocument(message):
            return "Invalid xctrace XML: \(message)"
        case .usage:
            return "Usage: script/analyze_cpu_trace.swift <exported-xml> [project-source-root]"
        }
    }
}

final class TraceReferences {
    private(set) var backtraces: [String: [XMLElement]] = [:]
    private(set) var binaries: [String: (name: String, path: String)] = [:]
    private(set) var frames: [String: XMLElement] = [:]
    private(set) var paths: [String: String] = [:]
    private(set) var threads: [String: String] = [:]
    private(set) var weights: [String: Double] = [:]

    init(document: XMLDocument) throws {
        try loadBinaries(document)
        try loadPaths(document)
        try loadFrames(document)
        try loadBacktraces(document)
        try loadThreads(document)
        try loadWeights(document)
    }

    func resolvedFrames(from element: XMLElement) -> [Frame] {
        let frameElements: [XMLElement]
        if let reference = element.attribute(forName: "ref")?.stringValue {
            frameElements = backtraces[reference] ?? []
        } else if element.name == "tagged-backtrace",
                  let nested = element.elements(forName: "backtrace").first {
            return resolvedFrames(from: nested)
        } else {
            frameElements = element.children?.compactMap { $0 as? XMLElement }
                .filter { $0.name == "frame" } ?? []
        }
        return frameElements.compactMap(resolveFrame)
    }

    func resolvedThreadName(from element: XMLElement?) -> String {
        guard let element else { return "unknown" }
        if let name = element.attribute(forName: "name")?.stringValue
            ?? element.attribute(forName: "fmt")?.stringValue {
            return name
        }
        if let reference = element.attribute(forName: "ref")?.stringValue {
            return threads[reference] ?? "unknown"
        }
        return element.stringValue ?? "unknown"
    }

    func resolvedWeight(from element: XMLElement?) -> Double {
        guard let element else { return 1 }
        if let reference = element.attribute(forName: "ref")?.stringValue {
            return weights[reference] ?? 1
        }
        return Self.parseWeight(
            element.attribute(forName: "fmt")?.stringValue ?? element.stringValue
        ) ?? 1
    }

    private func resolveFrame(_ element: XMLElement) -> Frame? {
        let definition: XMLElement
        if let reference = element.attribute(forName: "ref")?.stringValue {
            guard let stored = frames[reference] else { return nil }
            definition = stored
        } else {
            definition = element
        }

        let name = definition.attribute(forName: "name")?.stringValue
            ?? definition.stringValue
            ?? "unknown"
        guard let binaryElement = definition.elements(forName: "binary").first else {
            return Frame(
                name: name,
                binary: "unknown",
                path: "",
                sourcePath: sourcePath(from: definition)
            )
        }
        let binary: (name: String, path: String)
        if let reference = binaryElement.attribute(forName: "ref")?.stringValue {
            binary = binaries[reference] ?? ("unknown", "")
        } else {
            let path = binaryElement.attribute(forName: "path")?.stringValue ?? ""
            let name = binaryElement.attribute(forName: "name")?.stringValue
                ?? URL(fileURLWithPath: path).lastPathComponent
            binary = (name, path)
        }
        return Frame(
            name: name,
            binary: binary.name,
            path: binary.path,
            sourcePath: sourcePath(from: definition)
        )
    }

    private func loadBinaries(_ document: XMLDocument) throws {
        for element in try elements(document, xpath: "//binary[@id]") {
            guard let identifier = element.attribute(forName: "id")?.stringValue else { continue }
            let path = element.attribute(forName: "path")?.stringValue ?? ""
            let name = element.attribute(forName: "name")?.stringValue
                ?? URL(fileURLWithPath: path).lastPathComponent
            binaries[identifier] = (name, path)
        }
    }

    private func loadFrames(_ document: XMLDocument) throws {
        for element in try elements(document, xpath: "//frame[@id]") {
            guard let identifier = element.attribute(forName: "id")?.stringValue else { continue }
            frames[identifier] = element
        }
    }

    private func loadPaths(_ document: XMLDocument) throws {
        for element in try elements(document, xpath: "//path[@id]") {
            guard let identifier = element.attribute(forName: "id")?.stringValue,
                  let value = element.stringValue else {
                continue
            }
            paths[identifier] = value
        }
    }

    private func loadBacktraces(_ document: XMLDocument) throws {
        for element in try elements(document, xpath: "//backtrace[@id] | //stack[@id]") {
            guard let identifier = element.attribute(forName: "id")?.stringValue else { continue }
            backtraces[identifier] = element.children?.compactMap { $0 as? XMLElement }
                .filter { $0.name == "frame" } ?? []
        }
        for element in try elements(document, xpath: "//tagged-backtrace[@id]") {
            guard let identifier = element.attribute(forName: "id")?.stringValue,
                  let nested = element.elements(forName: "backtrace").first else {
                continue
            }
            backtraces[identifier] = nested.children?.compactMap { $0 as? XMLElement }
                .filter { $0.name == "frame" } ?? []
        }
    }

    private func loadThreads(_ document: XMLDocument) throws {
        for element in try elements(document, xpath: "//thread[@id]") {
            guard let identifier = element.attribute(forName: "id")?.stringValue else { continue }
            threads[identifier] = element.attribute(forName: "name")?.stringValue
                ?? element.attribute(forName: "fmt")?.stringValue
                ?? element.stringValue
                ?? "unknown"
        }
    }

    private func loadWeights(_ document: XMLDocument) throws {
        for name in ["weight", "cycle-weight"] {
            for element in try elements(document, xpath: "//\(name)[@id]") {
                guard let identifier = element.attribute(forName: "id")?.stringValue,
                      let value = Self.parseWeight(
                          element.attribute(forName: "fmt")?.stringValue ?? element.stringValue
                      ) else {
                    continue
                }
                weights[identifier] = value
            }
        }
    }

    private func elements(_ document: XMLDocument, xpath: String) throws -> [XMLElement] {
        try document.nodes(forXPath: xpath).compactMap { $0 as? XMLElement }
    }

    private func sourcePath(from frame: XMLElement) -> String {
        guard let pathElement = frame.elements(forName: "source").first?
            .elements(forName: "path").first else {
            return ""
        }
        if let reference = pathElement.attribute(forName: "ref")?.stringValue {
            return paths[reference] ?? ""
        }
        return pathElement.stringValue ?? ""
    }

    private static func parseWeight(_ value: String?) -> Double? {
        guard let value else { return nil }
        let scanner = Scanner(string: value)
        guard let number = scanner.scanDouble() else { return nil }
        if value.contains("µs") { return number / 1_000 }
        if value.contains("ns") { return number / 1_000_000 }
        if value.contains(" s") { return number * 1_000 }
        return number
    }
}

struct ProfileSummary {
    let projectSourceRoot: String
    let references: TraceReferences
    var aggregates: [String: Aggregate] = [:]
    var mainThreadWeight = 0.0
    var rowCount = 0
    var totalWeight = 0.0
    var userSampleCount = 0

    mutating func record(row: XMLElement) {
        let children = row.children?.compactMap { $0 as? XMLElement } ?? []
        guard let stack = children.first(where: {
            $0.name == "backtrace"
                || $0.name == "stack"
                || $0.name == "tagged-backtrace"
        }) else {
            return
        }

        let frames = references.resolvedFrames(from: stack)
        let weightElement = children.first {
            $0.name == "weight" || $0.name == "cycle-weight"
        }
        let weight = references.resolvedWeight(from: weightElement)
        let threadName = references.resolvedThreadName(
            from: children.first(where: { $0.name == "thread" })
        )

        rowCount += 1
        totalWeight += weight
        if threadName.localizedCaseInsensitiveContains("main") {
            mainThreadWeight += weight
        }

        let userFrames = frames.filter(isUserFrame)
        guard let selfFrame = userFrames.first else { return }
        userSampleCount += 1

        let selfKey = key(for: selfFrame)
        aggregates[selfKey, default: Aggregate()].selfWeight += weight
        aggregates[selfKey, default: Aggregate()].sampleCount += 1

        for frame in uniqueFrames(userFrames) {
            aggregates[key(for: frame), default: Aggregate()].inclusiveWeight += weight
        }
    }

    func printReport(limit: Int = 30) {
        print("support\tcpu-profile\t\(rowCount > 0 ? "available" : "partial")")
        print("rows\t\(rowCount)")
        print(String(format: "total_weight\t%.3f", totalWeight))
        print("user_samples\t\(userSampleCount)")
        let mainPercentage = totalWeight > 0 ? mainThreadWeight / totalWeight * 100 : 0
        print(String(format: "main_thread_weight_pct\t%.2f", mainPercentage))
        print("inclusive_pct\tself_pct\tsamples\tframe")

        let sorted = aggregates.sorted {
            if $0.value.inclusiveWeight != $1.value.inclusiveWeight {
                return $0.value.inclusiveWeight > $1.value.inclusiveWeight
            }
            return $0.value.selfWeight > $1.value.selfWeight
        }
        for (name, aggregate) in sorted.prefix(limit) {
            let inclusive = totalWeight > 0 ? aggregate.inclusiveWeight / totalWeight * 100 : 0
            let selfPercentage = totalWeight > 0 ? aggregate.selfWeight / totalWeight * 100 : 0
            print(String(
                format: "%.2f\t%.2f\t%d\t%@",
                inclusive,
                selfPercentage,
                aggregate.sampleCount,
                name
            ))
        }
    }

    private func isUserFrame(_ frame: Frame) -> Bool {
        frame.sourcePath.contains(projectSourceRoot)
            || (frame.sourcePath.isEmpty && frame.binary == "CaskHub")
    }

    private func uniqueFrames(_ frames: [Frame]) -> [Frame] {
        var seen: Set<String> = []
        return frames.filter { seen.insert(key(for: $0)).inserted }
    }

    private func key(for frame: Frame) -> String {
        "\(frame.binary): \(frame.name)"
    }
}

func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2 else {
        throw TraceAnalysisError.usage
    }
    let xmlURL = URL(fileURLWithPath: arguments[1])
    let sourceRoot = arguments.count > 2
        ? URL(fileURLWithPath: arguments[2]).standardizedFileURL.path
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("CaskHub")
            .standardizedFileURL.path
    let document = try XMLDocument(contentsOf: xmlURL, options: .nodePreserveAll)
    guard document.rootElement() != nil else {
        throw TraceAnalysisError.invalidDocument("missing root element")
    }
    let references = try TraceReferences(document: document)
    var summary = ProfileSummary(projectSourceRoot: sourceRoot, references: references)
    let rows = try document.nodes(forXPath: "//row").compactMap { $0 as? XMLElement }
    for row in rows {
        summary.record(row: row)
    }
    summary.printReport()
}

do {
    try run()
} catch {
    fputs("analyze_cpu_trace: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
