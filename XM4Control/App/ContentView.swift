import SwiftUI
import AVFoundation
import WidgetKit

struct ContentView: View {
    @StateObject private var scanner = BLEScanner()
    @StateObject private var eaProbe = SonyEAProbe()
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

                Section("Sony ExternalAccessory 診斷") {
                    Text("iPhone 已實機驗證 Sony GET 66 15 回覆；可選擇唯讀查詢或手動執行一次 ANC 循環 SET 68 15（需讀回確認）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重新搜尋 ExternalAccessory") { eaProbe.refresh() }
                    Button(eaProbe.probing ? "測試進行中" : "測試 Sony EASession 開啟") {
                        eaProbe.testSession()
                    }
                    .disabled(eaProbe.probing)
                    Button(eaProbe.probing ? "查詢進行中" : "讀取 XM4 目前 ANC 模式（不切換）") {
                        eaProbe.readANC()
                    }
                    .disabled(eaProbe.probing)
                    Button(eaProbe.probing ? "切換／查詢進行中" : "手動切換 XM4 下一模式（實際變更耳機）") {
                        eaProbe.cycleOnce()
                    }
                    .disabled(eaProbe.probing)
                    Text("只在靜止且安全的環境測試。每次按下只進行一次 ANC → 環境音 → 關閉 → ANC，先讀取模式並讀回驗證；失敗不自動重試。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(eaProbe.result)
                        .font(.caption)
                        .textSelection(.enabled)
                    ForEach(Array(eaProbe.details.enumerated()), id: \.offset) { item in
                        Text(item.element).font(.caption2).textSelection(.enabled)
                    }
                    ForEach(Array(eaProbe.trace.enumerated()), id: \.offset) { item in
                        Text(item.element).font(.caption2).textSelection(.enabled)
                    }
                    Button("複製 EA 診斷結果") {
                        UIPasteboard.general.string = ([eaProbe.result] + eaProbe.details + eaProbe.trace).joined(separator: "\n")
                    }
                }

                Section("捷徑與三模式") {
                    Label("已加入捷徑：檢查 XM4 音訊連線", systemImage: "checkmark.circle")
                    Text("ANC → 環境音 → 關閉 → ANC 已在 Windows RFCOMM Channel 9 實機驗證。")
                    Text("iOS ExternalAccessory 已實機讀到 Sony ANC 狀態。新增加的手動切換尚待 iPhone 確認；動作按鈕捷徑仍保持停用，避免未驗證的背景操作。")
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
            .onAppear { refreshAudioRoute(); eaProbe.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                refreshAudioRoute()
            }
        }
    }
}
