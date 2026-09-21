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

    static func commit(source: URL, subtitle: URL?, title: String, format: SaveFormat,
                       items: [SavedMedia]) throws -> SavedMedia {
        let id = UUID()
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r"))
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceExtension = source.pathExtension.lowercased()
        let validExtension = sourceExtension.range(of: #"^[a-z0-9]{1,10}$"#, options: .regularExpression) != nil
            ? sourceExtension : format.rawValue.lowercased()
        let name = "\(String((cleaned.isEmpty ? "다운로드" : cleaned).prefix(80)))-\(id.uuidString.prefix(8)).\(validExtension)"
        let destination = documents.appendingPathComponent(name)
        try FileManager.default.moveItem(at: source, to: destination)
        var subtitleName: String?
        do {
            if let subtitle {
                let ext = subtitle.pathExtension.isEmpty ? "vtt" : subtitle.pathExtension.lowercased()
                let name = destination.deletingPathExtension().lastPathComponent + "." + ext
                try FileManager.default.moveItem(at: subtitle, to: documents.appendingPathComponent(name))
                subtitleName = name
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        let count = (try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        let item = SavedMedia(id: id, title: title, filename: name, format: format,
                             createdAt: .now, byteCount: Int64(count), subtitleFilename: subtitleName,
                             fileExtension: validExtension)
        do { try persist([item] + items) }
        catch {
            try? FileManager.default.removeItem(at: destination)
            if let subtitleName { try? FileManager.default.removeItem(at: documents.appendingPathComponent(subtitleName)) }
            throw error
        }
        return item
    }
}
