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
        let appOptionsDisabled = model.isBusy || model.directYTDLPMode
        let outputChoices = model.format == .mp4
            ? OutputFormatPreset.videoChoices
            : OutputFormatPreset.audioChoices

        return VStack(alignment: .leading, spacing: 16) {
            Text("파일 형식 및 저장 옵션")
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
                        Label("확장자명", systemImage: "doc.badge.gearshape")
                            .font(.subheadline)

                        Spacer()

                        Picker("확장자명", selection: $model.outputFormatPreset) {
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

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("커스텀 명령어", systemImage: "terminal")
                        .font(.subheadline)
                    TextField("예: -f 'best[height<=720]'", text: $model.customArguments, axis: .vertical)
                        .lineLimit(2...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Text("옵션만 입력하거나 yt-dlp로 시작하세요. 링크는 위 입력란을 사용합니다. 입력하면 파일 형식·확장자·화질·자막 선택을 대신합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isBusy)

            NavigationLink {
                AdvancedOptionsView(model: model)
            } label: {
                ContentCard {
                    HStack(spacing: 12) {
                        Label("자막 옵션", systemImage: "slider.horizontal.2.square")
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

            Text("선택 옵션을 yt-dlp 명령 인수로 실행합니다. 확장자는 변환 없이 해당 원본을 선택하며, 화질은 상한입니다. 기본 동영상 모드는 영상·소리가 합쳐진 원본만 사용하므로 분리 스트림 전용 고화질은 지원하지 않습니다. FFmpeg 병합·변환과 외부 프로그램 실행은 지원하지 않습니다. 저장 위치와 파일명은 앱이 관리합니다.")
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
        model.resetAdvancedOptions()
        model.format = .mp4
        model.quality = .best
        model.customQuality = ""

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
        if rawDefaults == "1" || rawDefaults == "true" { model.customArguments = "-f b" }

        selectedTab = .download
        model.download()
    }
}
