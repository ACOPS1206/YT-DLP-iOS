import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("backgroundAudioKeepAlive") private var backgroundAudioKeepAlive = true
    @Bindable var model: DownloadModel

    var body: some View {
        NavigationStack {
            Form {
                Section("화면") {
                    Picker("모드", selection: $appearance) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                }

                Section {
                    Toggle("다운로드 실행 유지", isOn: $backgroundAudioKeepAlive)
                        .onChange(of: backgroundAudioKeepAlive) { _, enabled in
                            model.setBackgroundAudioEnabled(enabled)
                        }
                } header: {
                    Text("백그라운드")
                } footer: {
                    Text("다운로드 중에만 무음 오디오를 재생합니다. 통화, 시스템 리소스 제한 또는 앱 강제 종료 시 작업이 중단될 수 있습니다.")
                }

                Section {
                    Label("나의 iPhone/yt-dlp GUI", systemImage: "folder")
                } header: {
                    Text("저장 위치")
                } footer: {
                    Text("보관함의 공유 버튼을 사용해 다른 앱이나 폴더로 내보낼 수 있습니다.")
                }

                Section {
                    LabeledContent("현재 버전", value: model.activeYTDLPVersion)
                    LabeledContent("번들 버전", value: DownloadModel.bundledYTDLPVersion)
                    Button {
                        model.checkForEngineUpdate()
                    } label: {
                        if model.isCheckingEngineUpdate {
                            HStack {
                                ProgressView()
                                Text("업데이트 확인 중…")
                            }
                        } else {
                            Label("yt-dlp 업데이트", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(model.isCheckingEngineUpdate)
                    if model.activeYTDLPVersion != DownloadModel.bundledYTDLPVersion {
                        Button("번들 버전으로 복구", role: .destructive) {
                            model.restoreBundledEngine()
                        }
                        .disabled(model.isCheckingEngineUpdate)
                    }
                    if let status = model.engineUpdateStatus {
                        Text(status).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("다운로드 엔진")
                } footer: {
                    Text("PyPI의 최신 wheel을 SHA-256으로 검증해 앱 저장 공간에 설치합니다. 설치 또는 복구 후 앱을 완전히 종료하고 다시 열어 주세요.")
                }

                Section("앱 정보") {
                    LabeledContent("버전", value: "0.2.0")
                    Link("프로젝트 웹사이트", destination: URL(string: "https://github.com/ACOPS1206/YT-DLP-iOS")!)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}
