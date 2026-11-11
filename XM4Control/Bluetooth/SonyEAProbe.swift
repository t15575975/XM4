import Foundation
import Combine
import ExternalAccessory

/// Passive ExternalAccessory discovery plus an explicitly requested stream-open test.
/// No data is written to Sony accessories. MFi eligibility is NOT implied by discovery.
final class SonyEAProbe: ObservableObject {
    @Published private(set) var details: [String] = []
    @Published private(set) var result = "尚未檢查"
    @Published private(set) var probing = false

    private let sonyProtocols = [
        "jp.co.sony.songpal.mdr.link",
        "jp.co.sony.songpal.mdr.link2"
    ]
    private var session: EASession?

    func refresh() {
        closeSession()
        let accessories = EAAccessoryManager.shared().connectedAccessories
        var lines: [String] = ["ExternalAccessory 可見裝置：\(accessories.count)"]
        for accessory in accessories {
            lines.append("名稱：\(accessory.name)")
            lines.append("製造商：\(accessory.manufacturer)")
            lines.append("型號：\(accessory.modelNumber)")
            lines.append("連線狀態：\(accessory.isConnected)")
            lines.append("協定：\(accessory.protocolStrings.isEmpty ? "（未列出）" : accessory.protocolStrings.joined(separator: ", "))")
            lines.append("---")
        }
        details = lines
        let sony = accessories.filter { accessory in
            accessory.protocolStrings.contains(where: { sonyProtocols.contains($0) })
        }
        result = sony.isEmpty
            ? "未發現 Sony ExternalAccessory 協定（不能據此判定耳機未配對）"
            : "找到 \(sony.count) 個宣告 Sony 協定的裝置；尚未驗證 EASession 可用"
    }

    func testSession() {
        guard !probing else { return }
        closeSession()
        let accessories = EAAccessoryManager.shared().connectedAccessories
        guard let match = accessories.lazy.compactMap({ accessory -> (EAAccessory, String)? in
            guard let proto = self.sonyProtocols.first(where: { accessory.protocolStrings.contains($0) }) else {
                return nil
            }
            return (accessory, proto)
        }).first else {
            result = "沒有可測試的 Sony ExternalAccessory 裝置／協定"
            return
        }

        guard let opened = EASession(accessory: match.0, forProtocol: match.1) else {
            result = "EASession 建立失敗；公開 API 無法取得此協定的工作階段"
            return
        }

        session = opened
        probing = true
        result = "已建立 EASession 物件；正在測試唯讀 stream 開啟（不送出資料）"
        opened.inputStream?.open()
        opened.outputStream?.open()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak opened] in
            guard let self = self, self.probing, let streamSession = opened else { return }
            let input = streamSession.inputStream
            let output = streamSession.outputStream
            let inStatus = input.map { String(describing: $0.streamStatus) } ?? "nil"
            let outStatus = output.map { String(describing: $0.streamStatus) } ?? "nil"
            let inError = input?.streamError?.localizedDescription ?? "none"
            let outError = output?.streamError?.localizedDescription ?? "none"
            self.result = "EASession stream 狀態：input=\(inStatus), output=\(outStatus)；錯誤 input=\(inError), output=\(outError)。不代表 Sony ANC 指令已通過驗證。"
            self.closeSession()
        }
    }

    private func closeSession() {
        session?.inputStream?.close()
        session?.outputStream?.close()
        session = nil
        probing = false
    }

    deinit {
        session?.inputStream?.close()
        session?.outputStream?.close()
    }
}
