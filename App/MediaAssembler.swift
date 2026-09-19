import AVFoundation
import Foundation

enum MediaAssembler {
    static func assemble(video: URL, audio: URL?, destination: URL) async throws {
        guard let audio else {
            try FileManager.default.moveItem(at: video, to: destination)
            return
        }
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceVideo = videoTracks.first, let sourceAudio = audioTracks.first else {
            throw AppFailure(message: "영상 또는 오디오 트랙을 읽을 수 없습니다.")
        }
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let targetVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let targetAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppFailure(message: "MP4 파일을 구성할 수 없습니다.")
        }
        try targetVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideo, at: .zero)
        targetVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)
        try targetAudio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(videoDuration, audioDuration)),
                                        of: sourceAudio, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw AppFailure(message: "이 원본은 MP4로 저장할 수 없습니다.")
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: destination, as: .mp4)
    }
}
