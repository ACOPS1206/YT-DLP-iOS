import Foundation

struct SharedDownloadRequest: Codable, Identifiable {
    let id: UUID
    let link: String
    let format: String
    let quality: Int
    let ytdlpDefaults: Bool?
    let createdAt: Date

    init(link: String, format: String, quality: Int, ytdlpDefaults: Bool = false) {
        id = UUID(); self.link = link; self.format = format; self.quality = quality
        self.ytdlpDefaults = ytdlpDefaults; createdAt = .now
    }
}

enum SharedLinkParser {
    static func parse(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if valid(value) { return value }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap { $0.url?.absoluteString }.first(where: valid)
    }

    static func valid(_ link: String) -> Bool {
        guard let components = URLComponents(string: link),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return false }
        return true
    }

    static func deepLink(for request: SharedDownloadRequest) -> URL? {
        guard valid(request.link), ["MP4", "M4A"].contains(request.format),
              [0, 360, 480, 720, 1080, 1440, 2160].contains(request.quality) else { return nil }
        var components = URLComponents()
        components.scheme = "ytdlpgui"
        components.host = "download"
        components.queryItems = [
            URLQueryItem(name: "url", value: request.link),
            URLQueryItem(name: "format", value: request.format),
            URLQueryItem(name: "quality", value: String(request.quality)),
            URLQueryItem(name: "defaults", value: (request.ytdlpDefaults ?? false) ? "1" : "0"),
        ]
        return components.url
    }
}

enum SharedInbox {
    static func directory() throws -> URL {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw NSError(domain: "SharedInbox", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "공유 저장소에 접근할 수 없습니다. 앱과 공유 확장의 App Groups 서명을 확인해 주세요."])
        }
        let directory = container.appendingPathComponent("SharedDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func enqueue(_ request: SharedDownloadRequest, at folder: URL? = nil) throws {
        guard SharedLinkParser.valid(request.link), ["MP4", "M4A"].contains(request.format),
              [0, 360, 480, 720, 1080, 1440, 2160].contains(request.quality) else {
            throw NSError(domain: "SharedInbox", code: 2, userInfo: [NSLocalizedDescriptionKey: "올바른 링크와 저장 옵션을 선택해 주세요."])
        }
        let directory = try folder ?? self.directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(request.id.uuidString + ".json")
        try JSONEncoder().encode(request).write(to: file, options: .atomic)
    }

    static func next(at folder: URL? = nil) throws -> SharedDownloadRequest? {
        let directory = try folder ?? self.directory()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var requests: [SharedDownloadRequest] = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let request = try? JSONDecoder().decode(SharedDownloadRequest.self, from: data),
                  file.deletingPathExtension().lastPathComponent == request.id.uuidString,
                  SharedLinkParser.valid(request.link), ["MP4", "M4A"].contains(request.format),
                  [0, 360, 480, 720, 1080, 1440, 2160].contains(request.quality) else {
                try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("invalid"))
                continue
            }
            requests.append(request)
        }
        return requests.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }.first
    }

    static func consume(_ request: SharedDownloadRequest, at folder: URL? = nil) throws {
        let directory = try folder ?? self.directory()
        try FileManager.default.removeItem(at: directory.appendingPathComponent(request.id.uuidString + ".json"))
    }
}
