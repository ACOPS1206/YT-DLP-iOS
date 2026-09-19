import ActivityKit
import Foundation

@MainActor final class LiveActivityManager {
    private var activity: Activity<DownloadActivityAttributes>?
    private var serialUpdate: Task<Void, Never>?
    private var lastUpdate = Date.distantPast
    private var lastPhase = ""

    func reconcile() async {
        let interrupted = DownloadActivityAttributes.ContentState(title: "다운로드", phase: "작업이 중단되었습니다.",
            progress: nil, transfer: "", logs: ["앱을 다시 열어 다운로드를 시작해 주세요."], status: "interrupted", updatedAt: .now)
        for old in Activity<DownloadActivityAttributes>.activities {
            await old.end(ActivityContent(state: interrupted, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    func start(id: UUID, format: SaveFormat, state: DownloadActivityAttributes.ContentState) -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return "실시간 현황이 꺼져 있어 앱에서 진행 상태를 표시합니다." }
        do {
            activity = try Activity.request(attributes: DownloadActivityAttributes(downloadID: id, format: format.rawValue),
                content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(30)), pushType: nil)
            lastUpdate = .now; lastPhase = state.phase
            return nil
        } catch { return "실시간 현황을 시작하지 못했습니다. 앱에서 진행 상태를 확인할 수 있어요." }
    }

    func update(_ state: DownloadActivityAttributes.ContentState, force: Bool = false) {
        guard let activity else { return }
        let now = Date()
        guard force || state.phase != lastPhase || now.timeIntervalSince(lastUpdate) >= 1 else { return }
        lastUpdate = now; lastPhase = state.phase
        let previous = serialUpdate
        serialUpdate = Task {
            await previous?.value
            await activity.update(ActivityContent(state: state, staleDate: state.updatedAt.addingTimeInterval(30)))
        }
    }

    func finish(_ state: DownloadActivityAttributes.ContentState) async {
        await serialUpdate?.value
        serialUpdate = nil
        guard let activity else { return }
        self.activity = nil
        await activity.end(ActivityContent(state: state, staleDate: nil),
                           dismissalPolicy: .after(.now.addingTimeInterval(60)))
    }
}
