import SwiftUI

struct LogsView: View {
    let model: DownloadModel
    var body: some View {
        NavigationStack {
            Group {
                if model.logs.isEmpty {
                    ContentUnavailableView("아직 로그가 없어요", systemImage: "text.alignleft",
                                           description: Text("다운로드를 시작하면 진행 로그가 표시됩니다."))
                } else {
                    List {
                        Section("현재 또는 마지막 작업 · 최근 500개") {
                            ForEach(model.logs.reversed()) { entry in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(entry.date, format: .dateTime.hour().minute().second())
                                        Spacer()
                                        if entry.level != "info" { Text(entry.level == "warning" ? "안내" : "오류") }
                                    }.font(.caption).foregroundStyle(.secondary)
                                    Text(entry.message).font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }.padding(.vertical, 4)
                            }
                        }
                    }.scrollContentBackground(.hidden)
                }
            }
            .background(AppBackground())
            .navigationTitle("다운로드 로그")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: model.logs.map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.level)] \($0.message)" }.joined(separator: "\n")) {
                        Label("로그 공유", systemImage: "square.and.arrow.up")
                    }.disabled(model.logs.isEmpty)
                }
            }
        }
    }
}
