import Foundation
import AVFoundation

/// Passive observation of the *current audio output route* only.
/// This cannot identify all paired/connected Classic Bluetooth devices.
struct XM4AudioSnapshot {
    let checkedAt: Date
    let isXM4AudioOutput: Bool
    let outputNames: [String]

    var summary: String {
        isXM4AudioOutput ? "XM4 正在輸出音訊" : "未偵測到 XM4 音訊輸出"
    }

    var detail: String {
        if isXM4AudioOutput {
            return "iPhone 目前音訊輸出使用 WF-1000XM4。"
        }
        return "iPhone 目前沒有使用 XM4 作為音訊輸出；不代表耳機未配對或未連線。"
    }

    var shortcutsResult: String {
        "\(summary)。\(detail)"
    }
}

enum XM4AudioRoute {
    static func snapshot() -> XM4AudioSnapshot {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let active = outputs.contains { port in
            let name = port.portName.uppercased()
            let sonyName = name.contains("WF-1000XM4") || name.contains("WF1000XM4")
            return sonyName &&
                (port.portType == .bluetoothA2DP || port.portType == .bluetoothHFP)
        }
        return XM4AudioSnapshot(
            checkedAt: Date(),
            isXM4AudioOutput: active,
            outputNames: outputs.map(\.portName)
        )
    }
}
