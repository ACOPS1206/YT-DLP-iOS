import Foundation

enum DownloadLogStore {
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("last-download-log.json")
    }

    static func load() -> [DownloadLogEntry] {
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([DownloadLogEntry].self, from: data) else { return [] }
        return Array(entries.suffix(500))
    }

    static func save(_ entries: [DownloadLogEntry]) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(entries.suffix(500))).write(to: file, options: .atomic)
        } catch {
            // Logging must never turn an otherwise successful download into a failure.
        }
    }
}
