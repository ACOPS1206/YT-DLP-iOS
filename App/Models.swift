import Foundation
import SwiftUI

enum SaveFormat: String, CaseIterable, Identifiable, Codable {
    case mp4 = "MP4", m4a = "M4A"
    var id: String { rawValue }
    var symbol: String { self == .mp4 ? "video" : "waveform" }
    var title: String { self == .mp4 ? "동영상" : "오디오" }
    var detail: String { self == .mp4 ? "영상과 소리 함께" : "소리만 저장" }
}

enum Quality: Int, CaseIterable, Identifiable, Codable {
    case best = 0
    case p2160 = 2160, p1440 = 1440, p1080 = 1080, p720 = 720, p480 = 480, p360 = 360
    case custom = -1

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .best: "최고 품질"
        case .custom: "직접 입력"
        default: "\(rawValue)p 이하"
        }
    }
}

enum OutputFormatPreset: String, CaseIterable, Identifiable {
    case automatic, mp4, mov, webm, mkv, m4a, mp3, aac, flac, wav, opus, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "자동"
        case .custom: "직접 입력"
        default: rawValue.uppercased()
        }
    }

    static let videoChoices: [Self] = [.automatic, .mp4, .mov, .webm, .mkv, .custom]
    static let audioChoices: [Self] = [.automatic, .m4a, .mp3, .aac, .flac, .wav, .opus, .custom]
}

enum YTDLPPreset: String, CaseIterable, Identifiable {
    case none = ""
    case mp4, mkv, mp3, aac, sleep

    var id: String { rawValue }
    var title: String { self == .none ? "사용 안 함" : rawValue.uppercased() }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "시스템 설정"; case .light: "라이트"; case .dark: "다크" }
    }
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

struct MediaInfo: Decodable, Equatable {
    let title: String
    let author: String
    let duration: Double?
    let thumbnail: String?
    var durationLabel: String {
        guard let duration, duration.isFinite else { return "길이 정보 없음" }
        let seconds = max(0, Int(duration))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct EngineResult: Decodable {
    let ok: Bool
    let error: String?
    let cancelled: Bool?
    let info: MediaInfo?
    let video: String?
    let audio: String?
    let file: String?
    let subtitle: String?
    let version: String?
    let updated: Bool?
}

struct EngineEvent: Decodable {
    let phase: String
    let progress: Double?
    let speed: Double?
    let eta: Double?
    let message: String?
    let level: String?
    let info: MediaInfo?
}

struct DownloadLogEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let message: String
    let level: String

    init(message: String, level: String = "info") {
        id = UUID(); date = .now; self.message = message; self.level = level
    }
}

struct SavedMedia: Identifiable, Codable {
    let id: UUID
    let title: String
    let filename: String
    let format: SaveFormat
    let createdAt: Date
    let byteCount: Int64
    let subtitleFilename: String?
    let fileExtension: String?
    var url: URL { MediaLibrary.documents.appendingPathComponent(filename) }
    var subtitleURL: URL? {
        guard let subtitleFilename else { return nil }
        let url = MediaLibrary.documents.appendingPathComponent(subtitleFilename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var shareURLs: [URL] { [url] + (subtitleURL.map { [$0] } ?? []) }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
    var detailLabel: String {
        let container = (fileExtension?.isEmpty == false ? fileExtension!.uppercased() : format.rawValue)
        return [container, sizeLabel, subtitleURL == nil ? nil : "자막 포함"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
