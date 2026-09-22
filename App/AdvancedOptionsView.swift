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
                Text("제한 없이 yt-dlp 명령줄 인수를 입력할 수 있습니다. 한 글자라도 입력하면 메인 화면의 미디어 종류·화질·출력 포맷·yt-dlp 기본 사용·-t 프리셋을 무시하고 입력한 인수를 yt-dlp가 직접 해석합니다.")
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
                     ? "직접 yt-dlp 인수가 입력되어 있어 앱의 자막 설정은 현재 무시됩니다."
                     : "쉼표로 구분한 언어 코드를 순서대로 찾습니다. 예: ko,en.")
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
