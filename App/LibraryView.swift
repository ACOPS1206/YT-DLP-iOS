import QuickLook
import SwiftUI

struct LibraryView: View {
    @Bindable var model: DownloadModel
    @State private var previewURL: URL?
    @State private var pendingDelete: SavedMedia?

    var body: some View {
        NavigationStack {
            Group {
                if model.saved.isEmpty {
                    ContentUnavailableView("저장한 파일 없음", systemImage: "folder",
                                           description: Text("다운로드한 동영상과 오디오가 여기에 표시됩니다."))
                } else {
                    List {
                        ForEach(model.saved) { item in
                            HStack(spacing: 12) {
                                Button { previewURL = item.url } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.format.symbol)
                                            .font(.title2)
                                            .foregroundStyle(.tint)
                                            .frame(width: 32)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title).foregroundStyle(.primary).lineLimit(2)
                                            Text(item.detailLabel).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)

                                ShareLink(items: item.shareURLs) {
                                    Image(systemName: "square.and.arrow.up").frame(width: 32, height: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(item.title) 공유")
                            }
                            .swipeActions {
                                Button("삭제", systemImage: "trash", role: .destructive) { pendingDelete = item }
                            }
                            .contextMenu {
                                ShareLink(items: item.shareURLs) { Label("공유", systemImage: "square.and.arrow.up") }
                                Button("삭제", systemImage: "trash", role: .destructive) { pendingDelete = item }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("보관함")
            .quickLookPreview($previewURL)
            .confirmationDialog("이 파일을 삭제할까요?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("파일 삭제", role: .destructive) {
                    if let item = pendingDelete { model.remove(item) }
                    pendingDelete = nil
                }
                Button("취소", role: .cancel) { pendingDelete = nil }
            }
        }
    }
}
