import SwiftUI
import WidgetKit
import AppIntents

struct XM4StatusEntry: TimelineEntry {
    let date: Date
    let audio: XM4AudioSnapshot
}

struct XM4WidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> XM4StatusEntry {
        let now = Date()
        return XM4StatusEntry(date: now,
            audio: XM4AudioSnapshot(checkedAt: now, isXM4AudioOutput: false, outputNames: []))
    }

    func getSnapshot(in context: Context, completion: @escaping (XM4StatusEntry) -> Void) {
        let snap = XM4AudioRoute.snapshot()
        completion(XM4StatusEntry(date: snap.checkedAt, audio: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<XM4StatusEntry>) -> Void) {
        let snap = XM4AudioRoute.snapshot()
        completion(Timeline(entries: [XM4StatusEntry(date: snap.checkedAt, audio: snap)],
                            policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

/// One-tap exact targets. Widgets cannot assume that an optimistic tap
/// reflects the actual headset state; SonyEAProbe verifies via 67 15.
struct XM4ModeButtons: View {
    var body: some View {
        HStack(spacing: 7) {
            modeButton("降噪", systemImage: "ear.badge.waveform", mode: .anc)
            modeButton("環境音", systemImage: "waveform", mode: .ambient)
            modeButton("關閉", systemImage: "speaker.slash", mode: .off)
        }
    }

    private func modeButton(_ title: String, systemImage: String, mode: XM4ModeSelection) -> some View {
        Button(intent: XM4SetModeIntent(mode: mode)) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("設定 XM4 \(title)")
    }
}

struct XM4StatusWidgetView: View {
    let entry: XM4StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "headphones")
                    .foregroundStyle(entry.audio.isXM4AudioOutput ? .green : .secondary)
                Text("WF-1000XM4")
                    .font(.headline)
                    .lineLimit(1)
            }
            Text(entry.audio.isXM4AudioOutput ? "iPhone 音訊輸出中" : "未作為音訊輸出")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
            XM4ModeButtons()
            Spacer(minLength: 0)

            if family == .systemMedium {
                Text("點按後由耳機讀回確認；Widget 不顯示即時 ANC 狀態")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("直接設定模式")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
        .configurationDisplayName("XM4 三模式控制")
        .description("直接設定 WF-1000XM4 降噪／環境音／關閉；使用 Sony ExternalAccessory 指令與讀回驗證。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct XM4WidgetBundle: WidgetBundle {
    var body: some Widget {
        XM4StatusWidget()
    }
}
