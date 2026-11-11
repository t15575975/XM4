import SwiftUI
import AVFoundation
import WidgetKit

struct ContentView: View {
    @StateObject private var scanner = BLEScanner()
    @State private var audioRoute = XM4AudioRoute.snapshot()

    private func refreshAudioRoute() {
        audioRoute = XM4AudioRoute.snapshot()
        WidgetCenter.shared.reloadTimelines(ofKind: "XM4StatusWidget")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("iPhone 音訊連線") {
                    HStack(spacing: 10) {
                        Image(systemName: audioRoute.isXM4AudioOutput
                              ? "headphones.circle.fill" : "headphones.circle")
                            .font(.title)
                            .foregroundStyle(audioRoute.isXM4AudioOutput ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(audioRoute.summary).font(.headline)
                            Text(audioRoute.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("重新檢查音訊狀態") { refreshAudioRoute() }
                    Text("此處檢查的是目前音訊輸出路由。音訊未使用 XM4 時，不能據此判定耳機已斷線。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("BLE 偵測狀態") {
                    LabeledContent("XM4 BLE 研究連線",
                                   value: scanner.xm4BLEConnected ? "已建立 GATT 連線" : "未建立／無法確認")
                    if let lastSeen = scanner.lastXM4SeenAt {
                        LabeledContent("最近 BLE 廣播",
                                       value: lastSeen.formatted(date: .abbreviated, time: .shortened))
                    }
                    Text("BLE 廣播與 GATT 連線不等於 Sony Bluetooth Classic 音訊連線。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(scanner.isScanning ? "停止 BLE 搜尋" : "開始 BLE 搜尋") {
                        scanner.isScanning ? scanner.stop() : scanner.start()
                    }
                }

                Section("捷徑與三模式") {
                    Label("已加入捷徑：檢查 XM4 音訊連線", systemImage: "checkmark.circle")
                    Text("ANC → 環境音 → 關閉 → ANC 已在 Windows RFCOMM Channel 9 實機驗證。")
                    Text("iPhone 尚未驗證能直接開啟 Sony RFCOMM 控制通道。捷徑中的三模式操作目前會明確回報不支援，不會假裝已切換。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Widget 顯示音訊輸出快照與檢查時間；系統決定重新整理頻率。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("GATT 研究觀察") {
                    if let error = scanner.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(scanner.devices) { device in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.name).font(.headline)
                            Text("\(device.rssi) dBm").font(.caption)
                            Button("檢查 GATT 服務") { scanner.inspect(device.id) }
                                .font(.caption)
                            ForEach(device.details, id: \.self) { detail in
                                Text(detail).font(.caption2).textSelection(.enabled)
                            }
                        }
                    }
                    HStack {
                        Text("觀察數：\(scanner.observations.count)")
                        Spacer()
                        Button("複製") {
                            UIPasteboard.general.string = scanner.observations.joined(separator: "\n")
                        }
                        Button("清除") { scanner.clearObservations() }
                    }.font(.caption)
                    ForEach(Array(scanner.observations.enumerated()), id: \.offset) { item in
                        Text(item.element).font(.caption2).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("XM4Control")
            .onAppear { refreshAudioRoute() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                refreshAudioRoute()
            }
        }
    }
}
