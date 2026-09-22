import SwiftUI
import UIKit

struct ContentView: View {
    private enum AppTab: Hashable { case download, library, logs }

    @Bindable var model: DownloadModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.download
    @State private var showingSettings = false
    @FocusState private var linkFocused: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("다운로드", systemImage: "arrow.down", value: .download) {
                downloadView
            }
            Tab("보관함", systemImage: "folder", value: .library) {
                LibraryView(model: model)
            }
            Tab("로그", systemImage: "text.alignleft", value: .logs) {
                LogsView(model: model)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
        }
        .task {
            await model.resumeSharedDownloads()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.resumeSharedDownloads() }
            }
        }
        .onOpenURL(perform: open)
    }

    private var downloadView: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        intro
                        linkInput

                        if let info = model.info {
                            preview(info)
                        }

                        options

                        if model.isBusy {
                            activity
                        }

                        if let notice = model.liveActivityNotice {
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let message = model.errorMessage {
                            Label(message, systemImage: "exclamationmark.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("오류: \(message)")
                        }

                        if let item = model.lastSaved {
                            savedCard(item)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 118)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppBackground())

                downloadButton
            }
            // Keep the bottom action pinned to the physical screen bottom.
            // When the keyboard appears, it covers the button instead of
            // pushing the button upward with the keyboard safe area.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationTitle("yt-dlp GUI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("설정", systemImage: "gearshape") {
                        showingSettings = true
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        linkFocused = false
                    }
                }
            }
            .onChange(of: model.link) { _, _ in
                model.invalidatePreview()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("링크 하나로,\n간편하게 저장.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("동영상이나 오디오를 iPhone에 담아두세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var linkInput: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("동영상 링크", systemImage: "link")
                    .font(.subheadline.weight(.semibold))

                TextField("https://…", text: $model.link, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...3)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($linkFocused)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("linkInput")

                HStack {
                    PasteButton(payloadType: String.self) { values in
                        if let first = values.first {
                            model.link = first.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
                    .disabled(model.isBusy)

                    Spacer()

                    Button("정보 확인", systemImage: "arrow.up.right") {
                        linkFocused = false
                        model.inspect()
                    }
                    .font(.subheadline)
                    .buttonStyle(.glass)
                    .disabled(!model.hasValidLink || model.isBusy)
                }
            }
        }
    }

    private func preview(_ info: MediaInfo) -> some View {
        ContentCard {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: info.thumbnail.flatMap(URL.init(string:))) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ZStack {
                        Color(uiColor: .tertiarySystemFill)
                        Image(systemName: "play.rectangle")
                            .font(.title2)
                    }
                }
                .frame(width: 100, height: 68)
                .clipShape(.rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(info.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    if !info.author.isEmpty {
                        Text(info.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(info.durationLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var options: some View {
        let appOptionsDisabled = model.isBusy || model.useYTDLPDefaults || model.directYTDLPMode
        let outputChoices = model.format == .mp4
            ? OutputFormatPreset.videoChoices
            : OutputFormatPreset.audioChoices

        return VStack(alignment: .leading, spacing: 16) {
            Text("저장 옵션")
                .font(.headline)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(SaveFormat.allCases) { format in
                        FormatChoice(format: format, selected: model.format == format) {
                            model.format = format
                            let choices = format == .mp4
                                ? OutputFormatPreset.videoChoices
                                : OutputFormatPreset.audioChoices
                            if !choices.contains(model.outputFormatPreset) {
                                model.outputFormatPreset = .automatic
                                model.customOutputFormat = ""
                            }
                        }
                    }
                }
            }
            .disabled(appOptionsDisabled)

            ContentCard {
                Toggle(isOn: $model.useYTDLPDefaults) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("yt-dlp 기본 사용", systemImage: "shippingbox")
                            .font(.subheadline)
                        Text("원본 포맷과 품질 선택을 yt-dlp에 맡겨 그대로 다운로드")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isBusy || model.directYTDLPMode)
                .onChange(of: model.useYTDLPDefaults) { _, enabled in
                    if enabled { model.presetAlias = .none }
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("-t 프리셋", systemImage: "terminal")
                            .font(.subheadline)

                        Spacer()

                        Picker("-t 프리셋", selection: $model.presetAlias) {
                            ForEach(YTDLPPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if model.presetAlias != .none {
                        Text("yt-dlp의 -t \(model.presetAlias.rawValue) 프리셋을 직접 사용합니다. 다른 메인 다운로드 옵션은 무시됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isBusy || model.customArgumentsActive)
                .onChange(of: model.presetAlias) { _, preset in
                    if preset != .none { model.useYTDLPDefaults = false }
                }
            }

            if model.format == .mp4 {
                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("화질", systemImage: "slider.horizontal.3")
                                .font(.subheadline)

                            Spacer()

                            Picker("화질", selection: $model.quality) {
                                ForEach(Quality.allCases) { quality in
                                    Text(quality.title).tag(quality)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if model.quality == .custom {
                            HStack {
                                TextField("예: 900", text: $model.customQuality)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.plain)
                                Text("p 이하")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .disabled(appOptionsDisabled)
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("출력 포맷", systemImage: "doc.badge.gearshape")
                            .font(.subheadline)

                        Spacer()

                        Picker("출력 포맷", selection: $model.outputFormatPreset) {
                            ForEach(outputChoices) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if model.outputFormatPreset == .custom {
                        TextField(model.format == .mp4 ? "예: mp4, webm" : "예: m4a, opus",
                                  text: $model.customOutputFormat)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }

                    if !model.effectiveOutputExtension.isEmpty {
                        Text("요청 포맷: .\(model.effectiveOutputExtension)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(appOptionsDisabled)

            NavigationLink {
                AdvancedOptionsView(model: model)
            } label: {
                ContentCard {
                    HStack(spacing: 12) {
                        Label("자막 및 고급 옵션", systemImage: "slider.horizontal.2.square")
                            .font(.subheadline)

                        Spacer()

                        Text(model.advancedOptionsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            Text(
                model.customArgumentsActive
                    ? "직접 yt-dlp 인수가 입력되어 있어 메인 화면의 다운로드 옵션은 모두 무시됩니다."
                    : model.presetAlias != .none
                    ? "-t \(model.presetAlias.rawValue) 프리셋을 yt-dlp가 직접 실행합니다. FFmpeg가 필요한 프리셋은 iOS에서 실패할 수 있습니다."
                    : model.useYTDLPDefaults
                    ? "yt-dlp가 사이트에서 제공하는 원본 형식과 품질을 직접 선택합니다. 별도 영상·오디오 병합에 FFmpeg가 필요하면 실패할 수 있습니다."
                    : model.format == .mp4
                    ? "H.264를 우선하되 HEVC/AV1 MP4와 분리 오디오까지 자동 폴백합니다. MP4/MOV는 iOS에서 병합할 수 있습니다."
                    : "AAC/M4A를 우선하고, 선택한 출력 포맷의 원본 오디오가 있으면 그대로 저장합니다."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var activity: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(model.phaseLabel)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    if let progress = model.progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.monospacedDigit())
                    }
                }

                if let progress = model.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }

                HStack {
                    Text(model.transferLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("취소", role: .cancel) {
                        model.cancel()
                    }
                    .font(.caption)
                }

                if let line = model.logs.last {
                    Text(line.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button("전체 로그 보기", systemImage: "text.alignleft") {
                    selectedTab = .logs
                }
                .font(.caption)
                .buttonStyle(.glass)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func savedCard(_ item: SavedMedia) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("저장 완료", systemImage: "checkmark.circle.fill")
                    .font(.headline)

                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(2)

                Text(item.detailLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ShareLink(items: item.shareURLs) {
                    Label("파일 저장 또는 공유", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var downloadButton: some View {
        let isEnabled = model.hasValidLink && !model.isBusy

        return VStack(spacing: 10) {
            Button {
                linkFocused = false
                model.download()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.to.line")
                    Text(model.isBusy ? model.phaseLabel : "다운로드")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(isEnabled ? Color.black : Color.secondary)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .disabled(!isEnabled)
            .accessibilityIdentifier("downloadButton")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(.bar)
            .padding(.bottom, -96)
        }
        .padding(.horizontal, 12)
    }

    private func open(_ url: URL) {
        if url.scheme == "ytdlpgui", url.host == "logs" {
            selectedTab = .logs
            return
        }

        guard url.scheme == "ytdlpgui",
              url.host == "download",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let link = components.queryItems?.first(where: { $0.name == "url" })?.value,
              !model.isBusy else {
            return
        }

        model.link = link
        model.outputFormatPreset = .automatic
        model.customOutputFormat = ""
        model.presetAlias = .none
        model.customArguments = ""

        if let rawFormat = components.queryItems?.first(where: { $0.name == "format" })?.value,
           let format = SaveFormat(rawValue: rawFormat) {
            model.format = format
        }

        if let rawQuality = components.queryItems?.first(where: { $0.name == "quality" })?.value,
           let value = Int(rawQuality),
           let quality = Quality(rawValue: value) {
            model.quality = quality
        }

        let rawDefaults = components.queryItems?.first(where: { $0.name == "defaults" })?.value?.lowercased()
        model.useYTDLPDefaults = rawDefaults == "1" || rawDefaults == "true"
        if model.useYTDLPDefaults { model.presetAlias = .none }

        selectedTab = .download
        model.download()
    }
}
