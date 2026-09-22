import Foundation
import Observation
import UIKit

@MainActor @Observable
final class DownloadModel {
    static let bundledYTDLPVersion = "2026.08.19"

    var link = ""
    var format: SaveFormat = .mp4
    var quality: Quality = .best
    var customQuality = ""
    var outputFormatPreset: OutputFormatPreset = .automatic
    var customOutputFormat = ""
    var presetAlias: YTDLPPreset = .none
    var downloadSubtitles = false
    var subtitleLanguages = "ko,en"
    var allowAutomaticSubtitles = true
    var useYTDLPDefaults = false
    var customArguments = ""
    private(set) var info: MediaInfo?
    private(set) var saved = MediaLibrary.load()
    private(set) var lastSaved: SavedMedia?
    private(set) var isBusy = false
    private(set) var progress: Double?
    private(set) var phaseLabel = ""
    private(set) var errorMessage: String?
    private(set) var transferLabel = ""
    private(set) var logs = DownloadLogStore.load()
    var liveActivityNotice: String?
    private(set) var isCheckingEngineUpdate = false
    private(set) var engineUpdateStatus: String?

    var activeYTDLPVersion: String {
        let marker = Self.engineRoot.appendingPathComponent("current")
        guard let value = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return Self.bundledYTDLPVersion
        }
        return value
    }

    @ObservationIgnored private let engine = Engine()
    @ObservationIgnored private let liveActivity = LiveActivityManager()
    @ObservationIgnored private let backgroundAudio = BackgroundAudioKeepAlive()
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var activeOperation = ""
    @ObservationIgnored private var lastLogSave = Date.distantPast
    @ObservationIgnored private var stopSharedQueue = false
    @ObservationIgnored private var acceptEngineEvents = false
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var cancellationRequested = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var hasValidLink: Bool {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return false }
        return true
    }

    var customArgumentsActive: Bool {
        !customArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var directYTDLPMode: Bool {
        customArgumentsActive || presetAlias != .none
    }

    var effectiveQuality: Int {
        if quality == .custom {
            guard let value = Int(customQuality.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (144...4320).contains(value) else { return 0 }
            return value
        }
        return max(0, quality.rawValue)
    }

    var effectiveOutputExtension: String {
        let raw = outputFormatPreset == .custom ? customOutputFormat : outputFormatPreset.rawValue
        if outputFormatPreset == .automatic { return "" }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard value.range(of: "^[a-z0-9]{1,10}$", options: .regularExpression) != nil else { return "" }
        return value
    }

    var hasAdvancedOptions: Bool {
        downloadSubtitles || customArgumentsActive
    }

    var advancedOptionsSummary: String {
        if customArgumentsActive { return "직접 인수" }
        return downloadSubtitles ? "자막" : "기본값"
    }

    func resetAdvancedOptions() {
        downloadSubtitles = false
        subtitleLanguages = "ko,en"
        allowAutomaticSubtitles = true
        customArguments = ""
    }

    func checkForEngineUpdate() {
        guard !isCheckingEngineUpdate, !isBusy else { return }
        isCheckingEngineUpdate = true
        engineUpdateStatus = "최신 버전을 확인하는 중…"
        engine.prepare()
        Task {
            defer { isCheckingEngineUpdate = false }
            do {
                try FileManager.default.createDirectory(at: Self.engineRoot,
                                                        withIntermediateDirectories: true)
                let result = try await engine.updateEngine(directory: Self.engineRoot) { [weak self] event in
                    guard let self, event.phase == "updating" else { return }
                    if let progress = event.progress {
                        self.engineUpdateStatus = "업데이트 다운로드 중… \(Int(progress * 100))%"
                    } else {
                        self.engineUpdateStatus = "업데이트 다운로드 중…"
                    }
                }
                guard result.ok, let version = result.version else {
                    throw AppFailure(message: result.error ?? "yt-dlp 업데이트에 실패했습니다.")
                }
                engineUpdateStatus = result.updated == true
                    ? "yt-dlp \(version) 설치 완료 · 앱을 다시 열면 적용됩니다."
                    : "yt-dlp \(version) · 이미 최신 버전입니다."
            } catch {
                engineUpdateStatus = "업데이트 실패: \(error.localizedDescription)"
            }
        }
    }

    func restoreBundledEngine() {
        guard !isBusy, !isCheckingEngineUpdate else { return }
        try? FileManager.default.removeItem(at: Self.engineRoot.appendingPathComponent("current"))
        engineUpdateStatus = "번들 버전으로 복구했습니다. 앱을 다시 열면 적용됩니다."
    }

    private static var engineRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YTDLPEngine", isDirectory: true)
    }

    func invalidatePreview() {
        guard !isBusy else { return }
        info = nil; lastSaved = nil; errorMessage = nil
    }

    func inspect() { start(operation: "inspect") }
    func download() { start(operation: "download") }

    func cancel() {
        guard isBusy else { return }
        cancellationRequested = true
        stopSharedQueue = true
        backgroundAudio.stop()
        engine.cancel(); work?.cancel()
        phaseLabel = "취소하는 중…"
        appendLog("취소 요청")
        publishActivity(force: true)
    }

    func setBackgroundAudioEnabled(_ enabled: Bool) {
        guard activeOperation == "download", isBusy, !cancellationRequested else { return }
        if enabled { backgroundAudio.start() } else { backgroundAudio.stop() }
    }

    func resumeSharedDownloads() async {
        if !didBootstrap {
            didBootstrap = true
            await liveActivity.reconcile()
        }
        guard !isBusy, UIApplication.shared.applicationState == .active else { return }
        stopSharedQueue = false
        startNextSharedDownload()
    }

    private func startNextSharedDownload() {
        guard !isBusy, !stopSharedQueue, UIApplication.shared.applicationState == .active else { return }
        do {
            guard let request = try SharedInbox.next() else { return }
            // Remove only after parsing and checking all options; never enqueue an unvalidated URL.
            try SharedInbox.consume(request)
            link = request.link
            format = SaveFormat(rawValue: request.format) ?? .mp4
            quality = Quality(rawValue: request.quality) ?? .best
            useYTDLPDefaults = request.ytdlpDefaults ?? false
            info = nil
            start(operation: "download")
        } catch {
            // App Groups may be unavailable in an unsigned simulator/development build.
            appendLog(error.localizedDescription, level: "warning")
        }
    }

    private func appendLog(_ text: String, level: String = "info") {
        let clean = text.replacingOccurrences(of: "https?://\\S+", with: "[링크]", options: .regularExpression)
            .replacingOccurrences(of: "[\\r\\n]+", with: " ", options: .regularExpression)
        guard !clean.isEmpty else { return }
        if logs.last?.message == clean, logs.last?.level == level { return }
        logs.append(DownloadLogEntry(message: String(clean.prefix(400)), level: level))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
        if Date().timeIntervalSince(lastLogSave) >= 1 {
            DownloadLogStore.save(logs); lastLogSave = .now
        }
    }

    private func activityState(status: String = "running") -> DownloadActivityAttributes.ContentState {
        DownloadActivityAttributes.ContentState(title: String((info?.title ?? "\(format.title) 다운로드").prefix(80)),
            phase: phaseLabel, progress: progress, transfer: String(transferLabel.prefix(80)),
            logs: logs.suffix(2).map { String($0.message.prefix(100)) }, status: status, updatedAt: .now)
    }

    private func publishActivity(force: Bool = false) {
        guard activeOperation == "download" else { return }
        liveActivity.update(activityState(), force: force)
    }

    private func start(operation: String) {
        guard hasValidLink, !isBusy else { return }
        isBusy = true; errorMessage = nil; lastSaved = nil
        logs = []; lastLogSave = .distantPast; liveActivityNotice = nil; activeOperation = operation
        phaseLabel = "정보를 확인하는 중…"; progress = nil; transferLabel = ""
        let id = UUID(); operationID = id; cancellationRequested = false
        acceptEngineEvents = true
        appendLog(operation == "download" ? "다운로드 준비" : "동영상 정보 확인 시작")
        let sourceLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedFormat = format
        let selectedQuality = effectiveQuality
        let selectedOutputExtension = effectiveOutputExtension
        let selectedPresetAlias = presetAlias.rawValue
        let selectedSubtitles = downloadSubtitles
        let selectedSubtitleLanguages = subtitleLanguages
        let selectedAutomaticSubtitles = allowAutomaticSubtitles
        let selectedYTDLPDefaults = useYTDLPDefaults
        let selectedCustomArguments = customArguments
        engine.prepare()
        if operation == "download" {
            backgroundAudio.onWarning = { [weak self] message in
                self?.appendLog(message, level: "warning")
                self?.publishActivity(force: true)
            }
            if UserDefaults.standard.object(forKey: "backgroundAudioKeepAlive") as? Bool ?? true {
                backgroundAudio.start()
            }
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FinishDownload") { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if self.backgroundTask != .invalid {
                        UIApplication.shared.endBackgroundTask(self.backgroundTask)
                        self.backgroundTask = .invalid
                    }
                    // The finite completion grant must always be ended, even during audio playback.
                    if !self.backgroundAudio.isPlaying { self.cancel() }
                }
            }
        }
        work = Task {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ytdlp-\(id.uuidString)")
            defer {
                try? FileManager.default.removeItem(at: folder)
                isBusy = false; operationID = nil; work = nil; acceptEngineEvents = false
                activeOperation = ""
                backgroundAudio.stop()
                DownloadLogStore.save(logs)
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
                if !stopSharedQueue {
                    Task { @MainActor in self.startNextSharedDownload() }
                }
            }
            do {
                if operation == "download" {
                    liveActivityNotice = liveActivity.start(id: id, format: selectedFormat, state: activityState())
                    if let liveActivityNotice { appendLog(liveActivityNotice, level: "warning") }
                }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let result = try await engine.run(operation: operation, link: sourceLink, format: selectedFormat,
                                                  quality: selectedQuality, directory: folder,
                                                  outputExtension: selectedOutputExtension,
                                                  presetAlias: selectedPresetAlias,
                                                  downloadSubtitles: selectedSubtitles,
                                                  subtitleLanguages: selectedSubtitleLanguages,
                                                  allowAutomaticSubtitles: selectedAutomaticSubtitles,
                                                  useYTDLPDefaults: selectedYTDLPDefaults,
                                                  customArguments: selectedCustomArguments) { [weak self] event in
                    guard let self, self.operationID == id, self.acceptEngineEvents, !self.cancellationRequested else { return }
                    if event.phase == "log" {
                        if let message = event.message { self.appendLog(message, level: event.level ?? "info") }
                        self.publishActivity()
                        return
                    }
                    if event.phase == "metadata" {
                        self.info = event.info
                        self.publishActivity(force: true)
                        return
                    }
                    self.phaseLabel = event.phase == "extracting" ? "정보를 확인하는 중…" : "다운로드 중…"
                    self.progress = event.progress.map { min(1, max(0, $0)) }
                    if let speed = event.speed, speed.isFinite {
                        self.transferLabel = ByteCountFormatter.string(fromByteCount: Int64(max(0, speed)), countStyle: .file) + "/s"
                        if let eta = event.eta, eta.isFinite {
                            self.transferLabel += " · 약 \(Int(max(0, eta)))초 남음"
                        }
                    }
                    self.publishActivity()
                }
                acceptEngineEvents = false
                try Task.checkCancellation()
                if result.cancelled == true { throw CancellationError() }
                guard result.ok else { throw AppFailure(message: result.error ?? "다운로드에 실패했습니다.") }
                info = result.info
                guard operation == "download" else { return }
                phaseLabel = "파일을 준비하는 중…"; progress = nil; transferLabel = ""
                let selectedRawArguments = !selectedCustomArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let selectedPreset = !selectedPresetAlias.isEmpty
                let directYTDLPOutput = selectedRawArguments || selectedPreset || selectedYTDLPDefaults
                appendLog(directYTDLPOutput
                          ? "yt-dlp 결과 파일 저장 준비"
                          : (result.audio != nil && selectedFormat == .mp4 ? "영상·오디오 MP4 결합 시작" : "파일 저장 준비"))
                publishActivity(force: true)
                let output: URL
                if directYTDLPOutput {
                    guard let file = result.file else {
                        throw AppFailure(message: "yt-dlp 다운로드 결과 파일이 없습니다.")
                    }
                    output = URL(fileURLWithPath: file)
                } else if selectedFormat == .mp4 {
                    guard let video = result.video else { throw AppFailure(message: "동영상 파일이 없습니다.") }
                    let videoURL = URL(fileURLWithPath: video)
                    let requestedContainer = selectedOutputExtension
                    let mergeContainer = ["mp4", "mov"].contains(requestedContainer)
                        ? requestedContainer : (result.audio == nil ? "" : "mp4")
                    if let audio = result.audio {
                        output = folder.appendingPathComponent("output.\(mergeContainer.isEmpty ? "mp4" : mergeContainer)")
                        try await MediaAssembler.assemble(video: videoURL,
                                                          audio: URL(fileURLWithPath: audio), destination: output)
                    } else if !mergeContainer.isEmpty,
                              videoURL.pathExtension.lowercased() != mergeContainer {
                        output = folder.appendingPathComponent("output.\(mergeContainer)")
                        try await MediaAssembler.assemble(video: videoURL, audio: nil, destination: output)
                    } else {
                        output = videoURL
                    }
                } else {
                    guard let audio = result.audio else { throw AppFailure(message: "오디오 파일이 없습니다.") }
                    output = URL(fileURLWithPath: audio)
                }
                try Task.checkCancellation()
                let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "opus", "ogg", "oga", "flac", "wav", "alac"]
                let storedFormat: SaveFormat = directYTDLPOutput && audioExtensions.contains(output.pathExtension.lowercased())
                    ? .m4a : .mp4
                let item = try MediaLibrary.commit(source: output,
                                                    subtitle: directYTDLPOutput ? nil : result.subtitle.map(URL.init(fileURLWithPath:)),
                                                    title: result.info?.title ?? "다운로드",
                                                    format: directYTDLPOutput ? storedFormat : selectedFormat, items: saved)
                saved.insert(item, at: 0); lastSaved = item
                phaseLabel = "저장 완료"; progress = 1; transferLabel = ""
                appendLog("보관함 저장 완료")
                backgroundAudio.stop()
                await liveActivity.finish(activityState(status: "completed"))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                errorMessage = "작업을 취소했습니다."
                phaseLabel = "취소됨"; transferLabel = ""
                appendLog("다운로드 취소됨")
                backgroundAudio.stop()
                await liveActivity.finish(activityState(status: "cancelled"))
            } catch {
                errorMessage = error.localizedDescription
                phaseLabel = "다운로드 실패"; transferLabel = ""
                appendLog(error.localizedDescription, level: "error")
                stopSharedQueue = true
                backgroundAudio.stop()
                await liveActivity.finish(activityState(status: "failed"))
            }
        }
    }

    func remove(_ item: SavedMedia) {
        do {
            try FileManager.default.removeItem(at: item.url)
            if let subtitleURL = item.subtitleURL { try? FileManager.default.removeItem(at: subtitleURL) }
            saved.removeAll { $0.id == item.id }
            try MediaLibrary.persist(saved)
            if lastSaved?.id == item.id { lastSaved = nil }
        } catch { errorMessage = error.localizedDescription }
    }
}
