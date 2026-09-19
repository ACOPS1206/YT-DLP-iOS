import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("backgroundAudioKeepAlive") private var backgroundAudioKeepAlive = true
    @AppStorage("accentColor") private var accentColor = AccentColorChoice.monochrome.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("yellowActiveDownloadButton") private var yellowActiveDownloadButton = true
    @Bindable var model: DownloadModel

    var body: some View {
        NavigationStack {
            Form {
                Section(appText("화면", "Appearance")) {
                    Picker(appText("모드", "Mode"), selection: $appearance) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appText(appearance.title, appearance == .system ? "System" : appearance == .light ? "Light" : "Dark")).tag(appearance.rawValue)
                        }
                    }
                }

                Section(appText("개인화", "Personalization")) {
                    Picker(appText("강조 색상", "Accent Color"), selection: $accentColor) {
                        ForEach(AccentColorChoice.allCases) { choice in
                            HStack {
                                Circle().fill(choice.color).frame(width: 12, height: 12)
                                Text(choice.title)
                            }
                            .tag(choice.rawValue)
                        }
                    }
                    Picker(appText("언어", "Language"), selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }

                    Toggle(isOn: $yellowActiveDownloadButton) {
                        HStack(spacing: 8) {
                            Text(appText("활성 다운로드 버튼을 노란색으로", "Yellow Active Download Button"))
                            Text(appText("베타", "BETA"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.yellow.opacity(0.22), in: Capsule())
                        }
                    }
                }

                Section {
                    Toggle(appText("백그라운드에서 유지", "Keep Running in Background"), isOn: $backgroundAudioKeepAlive)
                        .onChange(of: backgroundAudioKeepAlive) { _, enabled in
                            model.setBackgroundAudioEnabled(enabled)
                        }
                } header: {
                    Text(appText("백그라운드", "Background"))
                } footer: {
                    Text("다운로드 중에만 무음 오디오를 재생합니다. 통화, 시스템 리소스 제한 또는 앱 강제 종료 시 작업이 중단될 수 있습니다.")
                }

                Section {
                    Label("나의 iPhone/yt-dlp GUI", systemImage: "folder")
                } header: {
                    Text(appText("저장 위치", "Save Location"))
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
                    Text(appText("다운로드 엔진", "Download Engine"))
                } footer: {
                    Text("PyPI의 최신 wheel을 SHA-256으로 검증해 앱 저장 공간에 설치합니다. 설치 또는 복구 후 앱을 완전히 종료하고 다시 열어 주세요.")
                }

                Section(appText("앱 정보", "App Info")) {
                    LabeledContent(appText("버전", "Version"), value: "2.5")
                    Link("GitHub", destination: URL(string: "https://github.com/ACOPS1206/YT-DLP-iOS")!)
                }
            }
            .navigationTitle(appText("설정", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(appText("완료", "Done")) { dismiss() }
                }
            }
        }
    }
}
