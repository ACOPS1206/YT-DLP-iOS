import ActivityKit
import Foundation

struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var phase: String
        var progress: Double?
        var transfer: String
        var logs: [String]
        var status: String
        var updatedAt: Date

        var isFinished: Bool { ["completed", "cancelled", "failed", "interrupted"].contains(status) }
        var fraction: Double? { progress.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } }
        var percentage: String { fraction.map { "\(Int($0 * 100))%" } ?? "…" }
        var symbol: String {
            switch status {
            case "completed": "checkmark.circle.fill"
            case "failed", "interrupted": "exclamationmark.circle"
            case "cancelled": "xmark.circle"
            default: "arrow.down"
            }
        }
    }
    let downloadID: UUID
    let format: String
}
