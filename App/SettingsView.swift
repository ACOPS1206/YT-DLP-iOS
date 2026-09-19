import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("backgroundAudioKeepAlive") private var backgroundAudioKeepAlive = true
    let model: DownloadModel

    var body: some View {
        NavigationStack {
            Form {
                Section("화면") {
                    Picker("모드", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                Section("백그라운드") {
                    Toggle("무음 오디오로 실행 유지", isOn: $backgroundAudioKeepAlive)
                        .onChange(of: backgroundAudioKeepAlive) { _, enabled in
                            model.setBackgroundAudioEnabled(enabled)
                        }
                    Text("다운로드 중에만 무음 오디오를 재생합니다. 완료·실패·취소 시 멈춥니다. 통화나 iOS의 앱 종료로 중단될 수 있습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("저장") {
                    Label("파일 앱 → 나의 iPhone → yt-dlp GUI", systemImage: "folder")
                    Text("다운로드한 파일은 보관함의 공유 버튼으로 다른 폴더에도 저장할 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("앱 정보") {
                    LabeledContent("버전", value: "0.1.0")
                    LabeledContent("다운로드 엔진", value: "앱에 포함된 yt-dlp")
                    Text("엔진 업데이트는 새 앱 버전으로 제공됩니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}
