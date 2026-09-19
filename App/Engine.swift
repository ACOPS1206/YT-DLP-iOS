import Foundation

final class Engine {
    private let queue = DispatchQueue(label: "app.ytdlpgui.python", qos: .userInitiated)

    func prepare() { PythonRuntime.prepareOperation() }
    func cancel() { PythonRuntime.cancel() }

    func updateEngine(directory: URL,
                      progress: @escaping @MainActor (EngineEvent) -> Void) async throws -> EngineResult {
        try await execute(payload: ["operation": "update_engine", "directory": directory.path],
                          progress: progress)
    }

    func run(operation: String, link: String, format: SaveFormat, quality: Quality, directory: URL,
             downloadSubtitles: Bool, subtitleLanguages: String, allowAutomaticSubtitles: Bool,
             preferredVideoFormatID: String, preferredAudioFormatID: String, customArguments: String,
             progress: @escaping @MainActor (EngineEvent) -> Void) async throws -> EngineResult {
        let payload: [String: Any] = ["operation": operation, "url": link,
                                     "format": format.rawValue, "quality": quality.rawValue,
                                     "directory": directory.path,
                                     "download_subtitles": downloadSubtitles,
                                     "subtitle_languages": subtitleLanguages,
                                     "automatic_subtitles": allowAutomaticSubtitles,
                                     "video_format_id": preferredVideoFormatID,
                                     "audio_format_id": preferredAudioFormatID,
                                     "custom_arguments": customArguments]
        return try await execute(payload: payload, progress: progress)
    }

    private func execute(payload: [String: Any],
                         progress: @escaping @MainActor (EngineEvent) -> Void) async throws -> EngineResult {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let request = String(data: data, encoding: .utf8) else {
            throw AppFailure(message: "다운로드 요청을 만들 수 없습니다.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let json = PythonRuntime.run(request: request) { raw in
                    guard let data = raw.data(using: .utf8),
                          let event = try? JSONDecoder().decode(EngineEvent.self, from: data) else { return }
                    DispatchQueue.main.async { progress(event) }
                }
                do {
                    guard let data = json.data(using: .utf8) else {
                        throw AppFailure(message: "다운로드 결과를 읽을 수 없습니다.")
                    }
                    continuation.resume(returning: try JSONDecoder().decode(EngineResult.self, from: data))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
