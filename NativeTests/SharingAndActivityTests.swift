import XCTest
@testable import YTDLPGUI

final class SharingAndActivityTests: XCTestCase {
    func testLinkExtractionFromSharedTitleAndText() {
        XCTAssertEqual(SharedLinkParser.parse("직접 만든 영상\nhttps://example.com/video?id=1"), "https://example.com/video?id=1")
        XCTAssertNil(SharedLinkParser.parse("파일만 공유됨"))
        XCTAssertFalse(SharedLinkParser.valid("file:///private/test.mp4"))
        XCTAssertFalse(SharedLinkParser.valid("https://user:secret@example.com/video"))
    }

    func testShareDeepLinkPreservesDownloadOptions() throws {
        let request = SharedDownloadRequest(link: "https://example.com/video?id=one&list=two",
                                            format: "M4A", quality: 720, originalFormat: true)
        let url = try XCTUnwrap(SharedLinkParser.deepLink(for: request))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "ytdlpgui")
        XCTAssertEqual(components.host, "download")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, request.link)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "format" })?.value, "M4A")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "quality" })?.value, "720")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "original" })?.value, "1")
    }

    func testSharedOptionsRoundTripAndConsumeOneItem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = SharedDownloadRequest(link: "https://example.com/one", format: "MP4", quality: 720)
        let second = SharedDownloadRequest(link: "https://example.com/two", format: "M4A", quality: 0)
        try SharedInbox.enqueue(first, at: folder)
        try SharedInbox.enqueue(second, at: folder)
        let read = try XCTUnwrap(SharedInbox.next(at: folder))
        XCTAssertEqual(read.id, first.id)
        XCTAssertEqual(read.quality, 720)
        try SharedInbox.consume(read, at: folder)
        XCTAssertEqual(try SharedInbox.next(at: folder)?.id, second.id)
    }

    func testCorruptRequestDoesNotBlockQueue() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let valid = SharedDownloadRequest(link: "https://example.com/one", format: "MP4", quality: 1080)
        try SharedInbox.enqueue(valid, at: folder)
        try Data("corrupt".utf8).write(to: folder.appendingPathComponent("bad.json"))
        XCTAssertEqual(try SharedInbox.next(at: folder)?.id, valid.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("bad.json").path))
    }

    func testInvalidFormatNeverEntersInbox() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertThrowsError(try SharedInbox.enqueue(SharedDownloadRequest(link: "https://example.com/one", format: "EXE", quality: 0), at: folder))
    }

    func testIndeterminateAndTerminalActivityStates() throws {
        var state = DownloadActivityAttributes.ContentState(title: "내 영상", phase: "정보 확인", progress: nil,
            transfer: "", logs: ["동영상 정보 확인 시작"], status: "running", updatedAt: .now)
        XCTAssertEqual(state.percentage, "…")
        XCTAssertFalse(state.isFinished)
        state.progress = 1.5
        XCTAssertEqual(state.percentage, "100%")
        state.status = "completed"
        XCTAssertTrue(state.isFinished)
        let restored = try JSONDecoder().decode(DownloadActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
    }
}
