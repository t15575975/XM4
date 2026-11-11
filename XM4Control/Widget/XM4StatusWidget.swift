import SwiftUI
import WidgetKit
import AppIntents

struct XM4StatusEntry: TimelineEntry {
    let date: Date
    let audio: XM4AudioSnapshot
    let isConnected: Bool
    let battery: XM4BatteryReading
}

struct XM4WidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> XM4StatusEntry {
        let now = Date()
        return XM4StatusEntry(date: now,
            audio: XM4AudioSnapshot(checkedAt: now, isXM4AudioOutput: false, outputNames: []),
            isConnected: false, battery: .unavailable)
    }

    func getSnapshot(in context: Context, completion: @escaping (XM4StatusEntry) -> Void) {
        // Gallery preview never opens a Sony control session.
        if context.isPreview {
            let snap = XM4AudioRoute.snapshot()
            completion(XM4StatusEntry(date: snap.checkedAt, audio: snap,
                                      isConnected: false, battery: .unavailable))
        } else {
            fetchStatus(completion: completion)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<XM4StatusEntry>) -> Void) {
        fetchStatus { entry in
            // A preferred refresh interval, not a real-time or guaranteed timer.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private func fetchStatus(completion: @escaping (XM4StatusEntry) -> Void) {
        DispatchQueue.main.async {
            let audio = XM4AudioRoute.snapshot()
            let connected = XM4AccessoryStatus.connected()
            guard connected else {
                completion(XM4StatusEntry(date: Date(), audio: audio,
                                          isConnected: false, battery: .unavailable))
                return
            }
            let reader = XM4BatteryReader()
            reader.read { battery in
                // Do not show controls if disconnected while the battery query ran.
                let stillConnected = XM4AccessoryStatus.connected()
                completion(XM4StatusEntry(date: Date(), audio: audio,
                    isConnected: stillConnected,
                    battery: stillConnected ? battery : .unavailable))
            }
        }
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

    private func percent(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)%"
    }

    private func batteryCell(_ name: String, value: Int?, symbol: String) -> some View {
        VStack(spacing: 2) {
            Label(name, systemImage: symbol)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(percent(value))
                .font(.system(.caption, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 9) {
            HStack(spacing: 6) {
                Image(systemName: "headphones")
                    .foregroundStyle(entry.isConnected ? .green : .secondary)
                Text("WF-1000XM4")
                    .font(.headline)
                    .lineLimit(1)
            }
            Text(entry.isConnected ? "已連線" : "未連線")
                .font(.caption)
                .foregroundStyle(entry.isConnected ? .green : .secondary)

            if entry.isConnected {
                HStack(spacing: 4) {
                    batteryCell("左耳", value: entry.battery.left, symbol: "ear")
                    batteryCell("右耳", value: entry.battery.right, symbol: "ear")
                    batteryCell("充電盒", value: entry.battery.caseLevel, symbol: "battery.50percent")
                }
                Spacer(minLength: 0)
                XM4ModeButtons()
            } else {
                Spacer(minLength: 0)
                Label("連線後顯示電量與模式控制", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if family == .systemMedium {
                Text("電量為最近查詢結果；未取得顯示 --")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("更新：\(entry.date.formatted(date: .omitted, time: .shortened))")
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
        .configurationDisplayName("XM4 三模式控制")
        .description("連線時顯示左右耳／充電盒電量與三模式按鈕；斷線時自動隱藏按鈕。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct XM4WidgetBundle: WidgetBundle {
    var body: some Widget {
        XM4StatusWidget()
    }
}
