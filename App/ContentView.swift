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
            Tab("다운로드", systemImage: "arrow.down", value: .download) { downloadView }
            Tab("보관함", systemImage: "folder", value: .library) { LibraryView(model: model) }
            Tab("로그", systemImage: "text.alignleft", value: .logs) { LogsView(model: model) }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
        .task { await model.resumeSharedDownloads() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.resumeSharedDownloads() } }
        }
        .onOpenURL(perform: open)
    }

    private var downloadView: some View {
        NavigationStack {
            Form {
                linkSection
                if let info = model.info { previewSection(info) }
                optionsSection
                if model.isBusy { progressSection }

                if let notice = model.liveActivityNotice {
                    Section {
                        Label(notice, systemImage: "info.circle").foregroundStyle(.secondary)
                    }
                }
                if let message = model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("오류: \(message)")
                    }
                }
                if let item = model.lastSaved { savedSection(item) }
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("다운로드")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("설정", systemImage: "gearshape") { showingSettings = true }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { linkFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) { primaryAction }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: model.link) { _, _ in model.invalidatePreview() }
        }
    }

    private var linkSection: some View {
        Section {
            TextField("https://…", text: $model.link, axis: .vertical)
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
                .labelStyle(.titleAndIcon)
                .disabled(model.isBusy)
                Spacer()
                Button("정보 확인", systemImage: "info.circle") {
                    linkFocused = false
                    model.inspect()
                }
                .disabled(!model.hasValidLink || model.isBusy)
            }
        } header: {
            Text("동영상 링크")
        } footer: {
            Text("저장할 동영상의 웹 주소를 입력하거나 붙여넣으세요.")
        }
    }

    private func previewSection(_ info: MediaInfo) -> some View {
        Section("미리보기") {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: info.thumbnail.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Color(uiColor: .tertiarySystemFill)
                        Image(systemName: "play.rectangle").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 54)
                .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title).font(.body.weight(.medium)).lineLimit(2)
                    if !info.author.isEmpty {
                        Text(info.author).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(info.durationLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var optionsSection: some View {
        Section {
            Picker("형식", selection: $model.format) {
                ForEach(SaveFormat.allCases) { format in
                    Label(format.rawValue, systemImage: format.symbol).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isBusy)

            if model.format == .mp4 {
                Picker("화질", selection: $model.quality) {
                    ForEach(Quality.allCases) { quality in Text(quality.title).tag(quality) }
                }
                .disabled(model.isBusy)
            } else {
                LabeledContent("음질", value: "원본 AAC")
            }

            NavigationLink {
                AdvancedOptionsView(model: model)
            } label: {
                LabeledContent("자막 및 고급 옵션", value: model.advancedOptionsSummary)
            }
            .disabled(model.isBusy)
        } header: {
            Text("저장 옵션")
        } footer: {
            Text(model.format == .mp4
                 ? "선택한 화질 이하의 호환 가능한 H.264 동영상을 저장합니다."
                 : "원본 AAC 오디오를 M4A 형식으로 저장합니다.")
        }
    }

    private var progressSection: some View {
        Section("진행 상황") {
            HStack {
                Text(model.phaseLabel)
                Spacer()
                if let progress = model.progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if let progress = model.progress { ProgressView(value: progress) }
            else { ProgressView() }
            if !model.transferLabel.isEmpty { LabeledContent("전송", value: model.transferLabel) }
            if let line = model.logs.last {
                Text(line.message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button("전체 로그 보기", systemImage: "text.alignleft") { selectedTab = .logs }
            Button("다운로드 취소", systemImage: "xmark.circle", role: .destructive) { model.cancel() }
        }
    }

    private func savedSection(_ item: SavedMedia) -> some View {
        Section("최근 저장") {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).lineLimit(2)
                    Text(item.detailLabel).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            ShareLink(items: item.shareURLs) {
                Label("파일 저장 또는 공유", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var primaryAction: some View {
        let isEnabled = model.hasValidLink && !model.isBusy

        return Button {
            linkFocused = false
            model.download()
        } label: {
            Label(model.isBusy ? model.phaseLabel : "다운로드", systemImage: "arrow.down.to.line")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(isEnabled ? Color(uiColor: .systemBackground) : Color.secondary)
                .background(
                    isEnabled ? Color.primary : Color(uiColor: .tertiarySystemFill),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier("downloadButton")
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func open(_ url: URL) {
        if url.scheme == "ytdlpgui", url.host == "logs" {
            selectedTab = .logs
            return
        }
        guard url.scheme == "ytdlpgui", url.host == "download",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let link = components.queryItems?.first(where: { $0.name == "url" })?.value,
              !model.isBusy else { return }
        model.link = link
        if let rawFormat = components.queryItems?.first(where: { $0.name == "format" })?.value,
           let format = SaveFormat(rawValue: rawFormat) {
            model.format = format
        }
        if let rawQuality = components.queryItems?.first(where: { $0.name == "quality" })?.value,
           let value = Int(rawQuality), let quality = Quality(rawValue: value) {
            model.quality = quality
        }
        selectedTab = .download
        model.download()
    }
}
