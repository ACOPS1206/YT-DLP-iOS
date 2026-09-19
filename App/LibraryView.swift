import SwiftUI
import QuickLook

struct LibraryView: View {
    @Bindable var model: DownloadModel
    @State private var previewURL: URL?
    @State private var pendingDelete: SavedMedia?

    var body: some View {
        NavigationStack {
            Group {
                if model.saved.isEmpty {
                    ContentUnavailableView("아직 저장한 파일이 없어요", systemImage: "folder",
                                           description: Text("다운로드한 동영상과 오디오가 여기에 표시됩니다."))
                } else {
                    List {
                        ForEach(model.saved) { item in
                            HStack(spacing: 14) {
                                Button { previewURL = item.url } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: item.format.symbol)
                                            .font(.title3).frame(width: 44, height: 44)
                                            .background(.quaternary, in: .rect(cornerRadius: 14))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                            Text("\(item.format.rawValue) · \(item.sizeLabel)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }.buttonStyle(.plain)
                                ShareLink(item: item.url) {
                                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                                }.buttonStyle(.borderless).accessibilityLabel("\(item.title) 공유")
                            }
                            .padding(.vertical, 4)
                            .swipeActions {
                                Button("삭제", role: .destructive) { pendingDelete = item }
                            }
                        }
                    }.scrollContentBackground(.hidden)
                }
            }
            .background(AppBackground())
            .navigationTitle("보관함")
            .quickLookPreview($previewURL)
            .confirmationDialog("이 파일을 삭제할까요?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("파일 삭제", role: .destructive) {
                    if let item = pendingDelete { model.remove(item) }
                    pendingDelete = nil
                }
            }
        }
    }
}
