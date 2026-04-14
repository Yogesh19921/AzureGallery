import Foundation
import Observation

// MARK: - Log Entry

struct LogEntry: Identifiable {
    enum Level: String {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
    }

    let id = UUID()
    let date: Date
    let level: Level
    let tag: String
    let message: String

    /// Full ISO-8601 timestamp so persisted lines can be age-filtered on reload.
    var formatted: String {
        let ts = LogEntry.fileFormatter.string(from: date)
        return "[\(ts)] [\(level.rawValue)] [\(tag)] \(message)"
    }

    /// UI-only short time (HH:mm:ss.SSS).
    var shortTime: String { LogEntry.displayFormatter.string(from: date) }

    private static let fileFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Parse a persisted line. Returns nil if the line is malformed or older than `maxAge`.
    static func parse(_ line: String, maxAge: TimeInterval) -> LogEntry? {
        // Format: [2026-04-13T22:05:03.000Z] [LEVEL] [tag] message
        guard line.hasPrefix("["),
              let closeBracket = line.firstIndex(of: "]") else { return nil }
        let tsStr = String(line[line.index(after: line.startIndex)..<closeBracket])
        guard let date = fileFormatter.date(from: tsStr),
              Date().timeIntervalSince(date) <= maxAge else { return nil }

        let rest = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
        let parts = rest.components(separatedBy: "] ")
        let level: Level
        if rest.hasPrefix("[ERROR]") { level = .error }
        else if rest.hasPrefix("[WARN]") { level = .warn }
        else { level = .info }
        let tag  = parts.count > 1 ? parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "[")) : "restored"
        let msg  = parts.count > 2 ? parts[2...].joined(separator: "] ") : rest
        return LogEntry(date: date, level: level, tag: tag, message: msg)
    }
}

// MARK: - AppLogger

/// In-memory log store with disk persistence in the Caches directory.
/// Entries older than `maxAge` (default: 24 hours) are dropped on load and
/// pruned from memory on every append, so the log never grows stale.
@Observable
@MainActor
final class AppLogger {
    static let shared = AppLogger()

    private(set) var entries: [LogEntry] = []

    /// Maximum entries kept in memory.
    private let maxEntries = 1_000
    /// Log entries older than this are silently discarded (24 hours).
    let maxAge: TimeInterval = 86_400

    private let logFileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("app_log.txt")
    }()

    private init() {
        loadFromDisk()
    }

    // MARK: - Logging

    func info(_ message: String, tag: String = "App") {
        append(LogEntry(date: Date(), level: .info, tag: tag, message: message))
    }

    func warn(_ message: String, tag: String = "App") {
        append(LogEntry(date: Date(), level: .warn, tag: tag, message: message))
    }

    func error(_ message: String, tag: String = "App") {
        append(LogEntry(date: Date(), level: .error, tag: tag, message: message))
    }

    // MARK: - Export / Clear

    func exportText() -> String {
        entries.map(\.formatted).joined(separator: "\n")
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: logFileURL)
    }

    // MARK: - Internals

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        pruneOldEntries()
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist(entry)
    }

    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        entries.removeAll { $0.date < cutoff }
    }

    private func persist(_ entry: LogEntry) {
        let line = entry.formatted + "\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = logFileURL
        DispatchQueue.global(qos: .utility).async {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadFromDisk() {
        guard let text = try? String(contentsOf: logFileURL, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        // Discard entries older than maxAge — the 24-hour purge happens here.
        let fresh = lines.compactMap { LogEntry.parse($0, maxAge: maxAge) }
        entries = Array(fresh.suffix(maxEntries))
        // Rewrite the file so stale entries don't accumulate on disk.
        if fresh.count < lines.count {
            let cleaned = entries.map { $0.formatted + "\n" }.joined()
            try? cleaned.data(using: .utf8)?.write(to: logFileURL, options: .atomic)
        }
    }
}
