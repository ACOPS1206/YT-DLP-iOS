import Foundation

enum MediaLibrary {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var manifest: URL { documents.appendingPathComponent("downloads.json") }

    static func load() -> [SavedMedia] {
        guard let data = try? Data(contentsOf: manifest),
              let items = try? JSONDecoder().decode([SavedMedia].self, from: data) else { return [] }
        return items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    static func persist(_ items: [SavedMedia]) throws {
        try JSONEncoder().encode(items).write(to: manifest, options: .atomic)
    }

    static func commit(source: URL, title: String, format: SaveFormat, items: [SavedMedia]) throws -> SavedMedia {
        let id = UUID()
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r"))
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = "\(String((cleaned.isEmpty ? "다운로드" : cleaned).prefix(80)))-\(id.uuidString.prefix(8)).\(format.rawValue.lowercased())"
        let destination = documents.appendingPathComponent(name)
        try FileManager.default.moveItem(at: source, to: destination)
        let count = (try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        let item = SavedMedia(id: id, title: title, filename: name, format: format,
                             createdAt: .now, byteCount: Int64(count))
        do { try persist([item] + items) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        return item
    }
}
