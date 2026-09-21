import SwiftUI

struct AdvancedOptionsView: View {
    @Bindable var model: DownloadModel

    var body: some View {
        Form {
            Section {
                Toggle("자막 다운로드", isOn: $model.downloadSubtitles)
                if model.downloadSubtitles {
                    TextField("언어 코드", text: $model.subtitleLanguages)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("자동 생성 자막 허용", isOn: $model.allowAutomaticSubtitles)
                }
            } header: {
                Text("자막")
            } footer: {
                Text("쉼표로 구분한 언어 코드를 순서대로 찾습니다. 예: ko,en. 자막은 미디어 파일과 함께 별도 파일로 저장됩니다.")
            }

            Section {
                TextField("자동 선택 · 예: mp4, webm", text: $model.preferredVideoExtension)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("자동 선택 · 예: m4a, webm", text: $model.preferredAudioExtension)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("원본 확장자")
            } footer: {
                Text("첫 번째 칸은 비디오, 두 번째 칸은 오디오 확장자입니다. 점(.) 없이 입력하세요. 비워 두면 앱이 가장 적절한 형식을 자동 선택합니다.")
            }

            Section {
                TextField("--socket-timeout 30", text: $model.customArguments, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("추가 yt-dlp 인자")
            } footer: {
                Text("지원: --socket-timeout, --retries, --fragment-retries, --user-agent, --referer, --add-header. 셸 명령, 출력 경로, 외부 프로그램 및 플러그인 옵션은 허용하지 않습니다.")
            }

            if model.hasAdvancedOptions {
                Section {
                    Button("고급 옵션 초기화", role: .destructive) {
                        model.resetAdvancedOptions()
                    }
                }
            }
        }
        .navigationTitle("고급 옵션")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isBusy)
    }
}
