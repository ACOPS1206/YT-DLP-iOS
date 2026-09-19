import ActivityKit
import SwiftUI
import WidgetKit

@main struct DownloadWidgets: WidgetBundle {
    var body: some Widget { DownloadLiveActivity() }
}

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("yt-dlp GUI", systemImage: context.state.symbol).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(context.state.percentage).font(.headline.monospacedDigit())
                }
                Text(context.state.title).font(.subheadline).lineLimit(1)
                ActivityProgress(state: context.state)
                ActivityLogs(state: context.state, stale: context.isStale)
            }
            .padding(16)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "ytdlpgui://logs"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.format, systemImage: context.state.symbol)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.percentage).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        ActivityProgress(state: context.state)
                        ActivityLogs(state: context.state, stale: context.isStale)
                    }.padding(.top, 5)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
            } compactTrailing: {
                Text(context.state.percentage).font(.caption2.monospacedDigit())
            } minimal: {
                if let progress = context.state.fraction, !context.state.isFinished {
                    Gauge(value: progress) { Image(systemName: "arrow.down") }
                        .gaugeStyle(.accessoryCircularCapacity).tint(.white)
                } else { Image(systemName: context.state.symbol) }
            }
            .keylineTint(.gray)
            .widgetURL(URL(string: "ytdlpgui://logs"))
        }
    }
}

private struct ActivityProgress: View {
    let state: DownloadActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 10) {
            if let progress = state.fraction {
                ProgressView(value: progress).tint(.primary)
                    .accessibilityLabel("다운로드 진행률")
            } else {
                Image(systemName: "ellipsis").accessibilityLabel("진행률 확인 중")
                Text(state.phase).font(.caption).lineLimit(1)
            }
            if !state.transfer.isEmpty { Text(state.transfer).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

private struct ActivityLogs: View {
    let state: DownloadActivityAttributes.ContentState
    let stale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stale && !state.isFinished ? "업데이트 대기 중 · 앱을 열어 확인" : state.phase)
                    .font(.caption.weight(.medium)).lineLimit(1)
                Spacer(minLength: 8)
                Text("로그 보기 ↗").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(state.logs.suffix(2).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
