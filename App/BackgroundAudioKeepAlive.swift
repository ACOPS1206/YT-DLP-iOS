import AVFoundation
import Foundation

/// Optional silent playback while a user-started download is running.
/// This cannot prevent force termination, memory eviction, or audio interruptions.
@MainActor
final class BackgroundAudioKeepAlive {
    private var player: AVAudioPlayer?
    private var requested = false
    private var ownsSession = false
    private var observers: [NSObjectProtocol] = []
    var onWarning: ((String) -> Void)?
    var isPlaying: Bool { player?.isPlaying == true }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                             object: nil, queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in
                guard let self, self.requested else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.player?.pause()
                    self.onWarning?("오디오 인터럽트로 백그라운드 유지가 중단되었습니다. 앱을 열어 진행 상태를 확인하세요.")
                } else if type == AVAudioSession.InterruptionType.ended.rawValue,
                          AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.play()
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player = nil
                if self.requested { self.play() }
            }
        })
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    func start() { requested = true; play() }

    func stop() {
        requested = false
        player?.stop(); player = nil
        deactivate()
    }

    private func deactivate() {
        guard ownsSession else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        ownsSession = false
    }

    private func play() {
        guard requested, !isPlaying else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            ownsSession = true
            guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else {
                throw AppFailure(message: "무음 오디오 리소스가 없습니다.")
            }
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.numberOfLoops = -1
            audio.volume = 1 // PCM samples are zero; no audible signal is generated.
            audio.prepareToPlay()
            guard audio.play() else { throw AppFailure(message: "무음 오디오 재생을 시작하지 못했습니다.") }
            player = audio
        } catch {
            player = nil
            deactivate()
            onWarning?("백그라운드 오디오 유지 실패: \(error.localizedDescription)")
        }
    }
}
