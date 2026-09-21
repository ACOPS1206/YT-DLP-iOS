import SwiftUI

struct AdvancedOptionsView: View {
    @Bindable var model: DownloadModel

    var body: some View {
        Form {
            Section {
                TextField("--format bestvideo+bestaudio --merge-output-format mp4",
                          text: $model.customArguments, axis: .vertical)
                    .lineLimit(2...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("yt-dlp 인수")
            } footer: {
                Text("제한 없이 yt-dlp 명령줄 인수를 입력할 수 있습니다. 이 칸에 인수가 하나라도 있으면 앱의 포맷·화질·원본 포맷·확장자·자막 등 다른 다운로드 옵션은 무시되고, 입력한 인수를 yt-dlp가 직접 해석합니다. 링크, 진행률 연결과 결과 파일 가져오기는 앱이 관리합니다.")
            }

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
                Text(model.customArgumentsActive
                     ? "직접 yt-dlp 인수가 입력되어 있어 이 설정은 현재 무시됩니다."
                     : "쉼표로 구분한 언어 코드를 순서대로 찾습니다. 예: ko,en. 자막은 미디어 파일과 함께 별도 파일로 저장됩니다.")
            }
            .disabled(model.customArgumentsActive)

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
                Text(model.customArgumentsActive
                     ? "직접 yt-dlp 인수가 입력되어 있어 이 설정은 현재 무시됩니다."
                     : "첫 번째 칸은 비디오, 두 번째 칸은 오디오 확장자입니다. 점(.) 없이 입력하세요. 비워 두면 앱이 가장 적절한 형식을 자동 선택합니다.")
            }
            .disabled(model.customArgumentsActive)

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
