import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareDownloadView(
            loadLink: { [weak self] in await self?.findLink() },
            openApp: { [weak self] request in await self?.openApp(with: request) ?? false },
            finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
        preferredContentSize = CGSize(width: 390, height: 480)
    }

    private func findLink() async -> String? {
        for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            for provider in item.attachments ?? [] {
                for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                    let text: String? = await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                            if let url = value as? URL { continuation.resume(returning: url.absoluteString) }
                            else if let string = value as? String { continuation.resume(returning: string) }
                            else if let data = value as? Data { continuation.resume(returning: String(data: data, encoding: .utf8)) }
                            else { continuation.resume(returning: nil) }
                        }
                    }
                    if let text, let link = SharedLinkParser.parse(text) { return link }
                }
            }
            if let text = item.attributedContentText?.string, let link = SharedLinkParser.parse(text) { return link }
        }
        return nil
    }

    private func openApp(with request: SharedDownloadRequest) async -> Bool {
        guard let url = SharedLinkParser.deepLink(for: request), let extensionContext else { return false }
        return await withCheckedContinuation { continuation in
            extensionContext.open(url) { opened in continuation.resume(returning: opened) }
        }
    }
}

private struct ShareDownloadView: View {
    let loadLink: () async -> String?
    let openApp: (SharedDownloadRequest) async -> Bool
    let finish: () -> Void
    @State private var link = ""
    @State private var format = "MP4"
    @State private var quality = 0
    @State private var originalFormat = false
    @State private var loading = true
    @State private var queued = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if queued {
                    Section {
                        Label("다운로드 대기열에 추가했어요", systemImage: "checkmark.circle.fill")
                        Text("완료를 누른 뒤 yt-dlp GUI 앱을 열면 선택한 옵션으로 다운로드를 시작합니다.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("공유된 링크") {
                        if loading { ProgressView("링크를 읽는 중…") }
                        TextField("https://…", text: $link, axis: .vertical)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section("저장 옵션") {
                        Picker("형식", selection: $format) {
                            Text("동영상 · MP4").tag("MP4")
                            Text("오디오 · M4A").tag("M4A")
                        }
                        if format == "MP4" {
                            Picker("화질", selection: $quality) {
                                Text("최고 화질").tag(0)
                                ForEach([1080, 720, 480], id: \.self) { Text("\($0)p 이하").tag($0) }
                            }
                        }
                        Toggle("원본 포맷", isOn: $originalFormat)
                    }
                    Section {
                        Button("앱에서 다운로드", systemImage: "arrow.down.to.line") { submit() }
                            .disabled(loading || !SharedLinkParser.valid(link))
                        Text("가능하면 앱을 바로 열고, 열 수 없으면 대기열에 안전하게 추가합니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.secondary) } }
            }
            .navigationTitle("yt-dlp GUI").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(queued ? "완료" : "닫기", action: finish) } }
            .task {
                link = await loadLink() ?? ""
                loading = false
                if link.isEmpty { error = "공유된 동영상 링크를 찾지 못했습니다. 링크를 직접 입력할 수 있어요." }
            }
        }
        .tint(.primary)
    }

    private func submit() {
        let request = SharedDownloadRequest(link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                                            format: format, quality: quality,
                                            originalFormat: originalFormat)
        loading = true
        error = nil
        Task {
            if await openApp(request) {
                finish()
                return
            }
            do {
                try SharedInbox.enqueue(request)
                queued = true
            } catch {
                self.error = "앱으로 링크를 전달하지 못했습니다: \(error.localizedDescription)"
            }
            loading = false
        }
    }
}
