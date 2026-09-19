import SwiftUI

struct LogsView: View {
    let model: DownloadModel

    var body: some View {
        NavigationStack {
            Group {
                if model.logs.isEmpty {
                    ContentUnavailableView(appText("로그 없음", "No Logs"), systemImage: "text.alignleft",
                                           description: Text("다운로드를 시작하면 진행 로그가 표시됩니다."))
                } else {
                    List {
                        Section("현재 또는 마지막 작업 · 최근 500개") {
                            ForEach(model.logs.reversed()) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        if entry.level != "info" {
                                            Image(systemName: entry.level == "warning"
                                                  ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                                                .foregroundStyle(entry.level == "warning" ? .orange : .red)
                                        }
                                        Text(entry.date, format: .dateTime.hour().minute().second())
                                        Spacer()
                                        if entry.level != "info" { Text(entry.level == "warning" ? "안내" : "오류") }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    Text(entry.message).font(.caption.monospaced()).textSelection(.enabled)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(appText("로그", "Logs"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: sharedLog) {
                        Label(appText("로그 공유", "Share Logs"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.logs.isEmpty)
                }
            }
        }
    }

    private var sharedLog: String {
        model.logs.map {
            "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.level)] \($0.message)"
        }.joined(separator: "\n")
    }
}
