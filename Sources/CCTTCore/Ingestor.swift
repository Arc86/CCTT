import Foundation

public struct ScanResult: Sendable, Equatable {
    public let events: [UsageEvent]
    public let parseErrors: Int
}

/// Reads new bytes from every `*.jsonl` under `projectsDir`, parsing only
/// content past each file's cached offset. Persists offsets after each scan.
public final class Ingestor {
    private let projectsDir: URL
    private let cacheURL: URL

    public init(projectsDir: URL, cacheURL: URL) {
        self.projectsDir = projectsDir
        self.cacheURL = cacheURL
    }

    public func scan() -> ScanResult {
        var cache = OffsetCache.load(from: cacheURL)
        var events: [UsageEvent] = []
        var parseErrors = 0

        for fileURL in jsonlFiles() {
            let path = fileURL.path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let inode = (attrs?[.systemFileNumber] as? UInt64) ?? 0
            let size = (attrs?[.size] as? UInt64) ?? 0
            let modTime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

            var startOffset: UInt64 = 0
            if let prior = cache[path] {
                // Reset to 0 on rotation (inode changed), shrinkage (truncation),
                // or an in-place rewrite that happens to leave the same size —
                // detected via a changed mtime, since inode+size alone can't
                // tell that apart from "nothing changed".
                let rotated = prior.inode != inode
                let shrunk = size < prior.byteOffset
                let rewrittenSameSize = size == prior.size && modTime != prior.modTime
                if !rotated && !shrunk && !rewrittenSameSize {
                    startOffset = prior.byteOffset
                }
            }
            if size == startOffset { // nothing new
                cache[path] = FileState(byteOffset: startOffset, inode: inode, size: size, modTime: modTime)
                continue
            }

            let (newEvents, errors, consumedTo) = readFrom(fileURL, offset: startOffset)
            events.append(contentsOf: newEvents)
            parseErrors += errors
            cache[path] = FileState(byteOffset: consumedTo, inode: inode, size: size, modTime: modTime)
        }

        try? cache.save(to: cacheURL)
        return ScanResult(events: events, parseErrors: parseErrors)
    }

    /// Returns parsed events, error count, and the absolute offset up to which
    /// complete lines were consumed (a partial trailing line is left unconsumed).
    private func readFrom(_ url: URL, offset: UInt64)
        -> (events: [UsageEvent], errors: Int, consumedTo: UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ([], 0, offset)
        }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return ([], 0, offset) }
        let data = (try? handle.readToEnd()) ?? Data()
        guard !data.isEmpty else { return ([], 0, offset) }

        // Find the last newline; only bytes up to and including it are complete.
        guard let lastNL = data.lastIndex(of: 0x0A) else {
            return ([], 0, offset) // no complete line yet
        }
        let completeData = data[data.startIndex...lastNL]
        var events: [UsageEvent] = []
        var errors = 0
        for lineData in completeData.split(separator: 0x0A, omittingEmptySubsequences: true) {
            switch JSONLParser.parseLine(Data(lineData)) {
            case .event(let e): events.append(e)
            case .malformed:    errors += 1
            case .skipped:      break
            }
        }
        let consumed = offset + UInt64(completeData.count)
        return (events, errors, consumed)
    }

    private func jsonlFiles() -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }
}

/// Ingestor's only stored state is two immutable, `Sendable` `URL`s, so this
/// conformance is a genuine `Sendable` type, not just a testability shim.
/// Must live in this file: Swift 6 requires `Sendable`-implying conformances
/// for a class to appear alongside its declaration.
extension Ingestor: UsageScanning {}
