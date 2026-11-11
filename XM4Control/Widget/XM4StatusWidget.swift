import SwiftUI
import WidgetKit

struct XM4StatusEntry: TimelineEntry {
    let date: Date
    let audio: XM4AudioSnapshot
}

struct XM4WidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> XM4StatusEntry {
        let now = Date()
        return XM4StatusEntry(
            date: now,
            audio: XM4AudioSnapshot(checkedAt: now, isXM4AudioOutput: false, outputNames: [])
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (XM4StatusEntry) -> Void) {
        let snap = XM4AudioRoute.snapshot()
        completion(XM4StatusEntry(date: snap.checkedAt, audio: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<XM4StatusEntry>) -> Void) {
        let snap = XM4AudioRoute.snapshot()
        let entry = XM4StatusEntry(date: snap.checkedAt, audio: snap)
        // WidgetKit controls update cadence. This is a snapshot, not a live Bluetooth monitor.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct XM4StatusWidgetView: View {
    let entry: XM4StatusEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "headphones")
                    .foregroundStyle(entry.audio.isXM4AudioOutput ? .green : .secondary)
                Text("WF-1000XM4")
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(entry.audio.isXM4AudioOutput ? "音訊輸出中" : "未作為音訊輸出")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(entry.audio.isXM4AudioOutput
                 ? "音訊路由已確認"
                 : "不代表藍牙已斷線")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if family == .systemMedium {
                Text("目前只偵測 iPhone 音訊路由；尚不能直接讀取 Sony Bluetooth Classic ANC 狀態。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("檢查於 \(entry.audio.checkedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct XM4StatusWidget: Widget {
    let kind = "XM4StatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: XM4WidgetProvider()) { entry in
            XM4StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("XM4 音訊連線")
        .description("顯示 WF-1000XM4 是否為目前的 iPhone 音訊輸出。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct XM4WidgetBundle: WidgetBundle {
    var body: some Widget {
        XM4StatusWidget()
    }
}
