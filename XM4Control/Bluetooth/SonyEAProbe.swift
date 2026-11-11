import Foundation
import Combine
import ExternalAccessory

/// Sony EASession research. Scanning is passive; the optional status request is
/// read-only from the user's point of view (it transmits GET 66 15 and protocol ACKs).
/// A user-triggered one-shot cycle requires valid before and after readings.
final class SonyEAProbe: NSObject, ObservableObject, StreamDelegate {
    static let shared = SonyEAProbe()

    /// Exact physical Sony control connection; an inactive iPhone audio route
    /// does not mean the headset is disconnected.
    static func isConnectedXM4() -> Bool {
        EAAccessoryManager.shared().connectedAccessories.contains { accessory in
            accessory.isConnected &&
            accessory.modelNumber == "WF-1000XM4" &&
            accessory.protocolStrings.contains("jp.co.sony.songpal.mdr.link2")
        }
    }
    @Published private(set) var details: [String] = []
    @Published private(set) var result = "尚未檢查"
    @Published private(set) var probing = false
    @Published private(set) var trace: [String] = []

    private let sonyProtocols = [
        "jp.co.sony.songpal.mdr.link2",
        "jp.co.sony.songpal.mdr.link"
    ]
    private var session: EASession?
    private var buffer = [UInt8]()
    private var pending = [UInt8]()
    private var readOnlyQuery = false
    private var cycleRequested = false
    private var waitingForSetAck = false
    private var waitingForReadback = false
    private var verifiedCycle = false
    private var expectedMode = ""
    private var fixedTargetMode: String?
    private var receivedState = false
    private var querySent = false
    private var sequence: UInt8 = 0
    private var generation = 0
    private var shortcutCompletion: ((Bool, String) -> Void)?

    func refresh() {
        guard !probing else { return }
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
        let sony = accessories.filter {
            $0.protocolStrings.contains(where: { sonyProtocols.contains($0) })
        }
        result = sony.isEmpty
            ? "未發現 Sony ExternalAccessory 協定（不代表耳機未配對）"
            : "找到 \(sony.count) 個 Sony 協定裝置；可測試 EASession 或唯讀 ANC 查詢"
    }

    func testSession() {
        start(query: false)
    }

    func readANC() {
        start(query: true)
    }

    func cycleOnce(completion: ((Bool, String) -> Void)? = nil) {
        beginModeChange(target: nil, completion: completion)
    }

    func setMode(_ mode: String, completion: ((Bool, String) -> Void)? = nil) {
        guard ["ANC", "AMBIENT", "OFF"].contains(mode) else {
            completion?(false, "模式無效；沒有送出指令。")
            return
        }
        beginModeChange(target: mode, completion: completion)
    }

    private func beginModeChange(target: String?, completion: ((Bool, String) -> Void)?) {
        guard !probing else {
            completion?(false, "已有 XM4 控制操作進行中；本次未再送出指令。")
            return
        }
        fixedTargetMode = target
        shortcutCompletion = completion
        start(query: true, cycle: true)
    }

    private func completeShortcut() {
        guard let completion = shortcutCompletion else { return }
        shortcutCompletion = nil
        completion(verifiedCycle, result)
    }

    private func start(query: Bool, cycle: Bool = false) {
        guard !probing else { return }
        closeSession()
        trace = []
        let accessories = EAAccessoryManager.shared().connectedAccessories
        guard let match = accessories.lazy.compactMap({ accessory -> (EAAccessory, String)? in
            guard accessory.modelNumber == "WF-1000XM4",
                  let proto = self.sonyProtocols.first(where: { accessory.protocolStrings.contains($0) })
            else { return nil }
            return (accessory, proto)
        }).first else {
            result = "未找到 WF-1000XM4 的 Sony 協定；沒有送出指令"
            completeShortcut()
            return
        }
        guard let opened = EASession(accessory: match.0, forProtocol: match.1),
              let input = opened.inputStream, let output = opened.outputStream else {
            result = "EASession 無法建立；沒有送出指令"
            completeShortcut()
            return
        }
        session = opened
        readOnlyQuery = query
        cycleRequested = cycle
        waitingForSetAck = false
        waitingForReadback = false
        verifiedCycle = false
        expectedMode = ""
        receivedState = false
        querySent = false
        sequence = 0
        buffer.removeAll()
        pending.removeAll()
        probing = true
        generation += 1
        let token = generation
        addTrace("Protocol: \(match.1); action: \(cycle ? (fixedTargetMode ?? "ONE cycle") : (query ? "GET ANC only" : "stream-open only"))")

        for stream in [input as Stream, output as Stream] {
            stream.delegate = self
            stream.schedule(in: .main, forMode: .common)
            stream.open()
        }
        result = cycle ? "先讀取 ANC 狀態，再單次切換並讀回…" : (query ? "正在開啟串流並等待發送唯讀 ANC 查詢…" : "正在檢查 EASession 串流…")

        DispatchQueue.main.asyncAfter(deadline: .now() + (cycle ? 10 : (query ? 6 : 2))) { [weak self] in
            guard let self = self, self.probing, self.generation == token else { return }
            let inputStatus = String(describing: input.streamStatus)
            let outputStatus = String(describing: output.streamStatus)
            self.addTrace("Stream end: input=\(inputStatus) output=\(outputStatus)")
            if query {
                if cycle {
                    if !self.verifiedCycle {
                        self.result = "切換未確認：未讀回目標模式，可能已切換；請以官方 App 核對，不自動重試。"
                    }
                } else if !self.receivedState {
                    self.result = "未取得有效 67 15 ANC 回覆；GET sent=\(self.querySent)。未切換模式。"
                }
            } else {
                self.result = "EASession stream 狀態：input=\(inputStatus), output=\(outputStatus)；錯誤 input=\(input.streamError?.localizedDescription ?? "none"), output=\(output.streamError?.localizedDescription ?? "none")"
            }
            self.completeShortcut()
            self.closeSession()
        }
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard probing else { return }
        if eventCode.contains(.errorOccurred) {
            addTrace("Stream error: \(aStream.streamError?.localizedDescription ?? "unknown")")
            result = "串流錯誤；無法確認 ANC 狀態"
            completeShortcut()
            closeSession()
            return
        }
        if eventCode.contains(.endEncountered) {
            addTrace("Stream ended")
            if !verifiedCycle { result = "耳機關閉串流，切換未經讀回確認" }
            completeShortcut()
            closeSession()
            return
        }
        if eventCode.contains(.hasBytesAvailable), let input = session?.inputStream {
            read(input)
        }
        if eventCode.contains(.hasSpaceAvailable), let output = session?.outputStream {
            if readOnlyQuery && !querySent && output.streamStatus == .open {
                querySent = true
                addTrace("TX: ANC GET 66 15")
                enqueue(encode(type: 0x0C, sequence: sequence, payload: [0x66, 0x15]))
                sequence ^= 1
            }
            flush(output)
        }
        if eventCode.contains(.openCompleted) {
            addTrace("Stream opened")
            if readOnlyQuery && !querySent,
               let output = session?.outputStream, output.hasSpaceAvailable {
                querySent = true
                addTrace("TX: ANC GET 66 15")
                enqueue(encode(type: 0x0C, sequence: sequence, payload: [0x66, 0x15]))
                sequence ^= 1
                flush(output)
            }
        }
    }

    private func enqueue(_ bytes: [UInt8]) {
        pending.append(contentsOf: bytes)
        if let output = session?.outputStream, output.hasSpaceAvailable { flush(output) }
    }

    private func flush(_ output: OutputStream) {
        guard !pending.isEmpty, output.hasSpaceAvailable else { return }
        let count = pending.withUnsafeBufferPointer { ptr in
            output.write(ptr.baseAddress!, maxLength: ptr.count)
        }
        if count > 0 {
            pending.removeFirst(count)
        } else if count < 0 {
            addTrace("TX error: \(output.streamError?.localizedDescription ?? "unknown")")
            result = "無法傳送查詢／切換指令"
            completeShortcut()
            closeSession()
        }
    }

    private func read(_ input: InputStream) {
        var chunk = [UInt8](repeating: 0, count: 512)
        while input.hasBytesAvailable {
            let n = input.read(&chunk, maxLength: chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk.prefix(n))
            if buffer.count > 4096 {
                addTrace("RX buffer exceeded safety limit")
                result = "收到過量資料，停止查詢"
                completeShortcut()
                closeSession()
                return
            }
            parseFrames()
        }
    }

    private func parseFrames() {
        while let start = buffer.firstIndex(of: 0x3E) {
            if start > 0 { buffer.removeFirst(start) }
            guard let end = buffer.dropFirst().firstIndex(of: 0x3C) else { return }
            let wire = Array(buffer[1..<end])
            buffer.removeFirst(end + 1)
            var body = [UInt8]()
            var i = 0
            var valid = true
            while i < wire.count {
                let byte = wire[i]
                if byte == 0x3D {
                    i += 1
                    guard i < wire.count else { valid = false; break }
                    switch wire[i] {
                    case 0x2C: body.append(0x3C)
                    case 0x2D: body.append(0x3D)
                    case 0x2E: body.append(0x3E)
                    default: valid = false
                    }
                } else {
                    body.append(byte)
                }
                i += 1
            }
            guard valid, body.count >= 7 else { addTrace("Malformed RX frame"); continue }
            let length = (UInt32(body[2]) << 24) | (UInt32(body[3]) << 16) |
                         (UInt32(body[4]) << 8) | UInt32(body[5])
            guard length <= 1024, body.count == Int(length) + 7 else {
                addTrace("Invalid RX frame length")
                continue
            }
            let expected = body.dropLast().reduce(UInt8(0)) { $0 &+ $1 }
            guard expected == body.last else { addTrace("RX checksum mismatch"); continue }
            let type = body[0], receivedSequence = body[1]
            let payload = Array(body[6..<(6 + Int(length))])
            addTrace("RX type=\(hex(type)) seq=\(receivedSequence) payload=\(payload.map(hex).joined(separator: " "))")
            if type == 0x01 && receivedSequence < 2 {
                sequence = receivedSequence
                if waitingForSetAck {
                    waitingForSetAck = false
                    waitingForReadback = true
                    addTrace("SET ACK; querying independent readback")
                    sendGet()
                }
            }
            if type == 0x0C {
                enqueue(encode(type: 0x01, sequence: 1 &- (receivedSequence & 1), payload: []))
            }
            if type == 0x0C && payload.count == 8 &&
                payload[0] == 0x67 && payload[1] == 0x15 &&
                payload[2] == 1 && payload[3] <= 1 &&
                payload[4] <= 1 && payload[6] <= 1 && payload[7] <= 20 {
                let mode = payload[3] == 0 ? "OFF" : (payload[4] == 1 ? "AMBIENT" : "ANC")
                receivedState = true
                if waitingForReadback {
                    waitingForReadback = false
                    if mode == expectedMode {
                        verifiedCycle = true
                        result = "三模式切換已驗證：目前 \(mode)，已收到獨立讀回。"
                        addTrace("VERIFIED mode=\(mode)")
                        DispatchQueue.main.async { [weak self] in
                            self?.completeShortcut()
                            self?.closeSession()
                        }
                    } else {
                        result = "切換未驗證：預期 \(expectedMode)，讀回 \(mode)，不重試。"
                        addTrace("READBACK MISMATCH expected=\(expectedMode) actual=\(mode)")
                        DispatchQueue.main.async { [weak self] in
                            self?.completeShortcut()
                            self?.closeSession()
                        }
                    }
                } else if cycleRequested && expectedMode.isEmpty {
                    let next = fixedTargetMode ?? (mode == "ANC" ? "AMBIENT" : (mode == "AMBIENT" ? "OFF" : "ANC"))
                    expectedMode = next
                    if mode == next {
                        verifiedCycle = true
                        result = "耳機原本已是 \(next)，有效狀態讀取已確認；無需 SET。"
                        addTrace("ALREADY mode=\(next); no SET")
                        DispatchQueue.main.async { [weak self] in
                            self?.completeShortcut()
                            self?.closeSession()
                        }
                        continue
                    }
                    let enable: UInt8 = next == "OFF" ? 0 : 1
                    let ambient: UInt8 = next == "AMBIENT" ? 1 : 0
                    let level: UInt8 = payload[7] == 0 ? 1 : payload[7]
                    let setPayload: [UInt8] = [0x68, 0x15, 0x01, enable, ambient, payload[5], payload[6], level]
                    addTrace("BEFORE \(mode); SET \(next); wind=\(payload[5]) voice=\(payload[6]) level=\(level)")
                    result = "已讀取 \(mode)，請求單次切換到 \(next)，等待讀回…"
                    waitingForSetAck = true
                    enqueue(encode(type: 0x0C, sequence: sequence, payload: setPayload))
                    sequence ^= 1
                } else if !cycleRequested {
                    result = "已收到有效 Sony ANC 狀態：\(mode)，環境音等級 \(payload[7])。未更改任何模式。"
                }
            }
        }
        if buffer.firstIndex(of: 0x3E) == nil { buffer.removeAll() }
    }

    private func sendGet() {
        addTrace("TX: ANC GET 66 15 (readback)")
        enqueue(encode(type: 0x0C, sequence: sequence, payload: [0x66, 0x15]))
        sequence ^= 1
    }

    private func encode(type: UInt8, sequence: UInt8, payload: [UInt8]) -> [UInt8] {
        var body: [UInt8] = [type, sequence, 0, 0, 0, UInt8(payload.count)]
        body.append(contentsOf: payload)
        body.append(body.reduce(UInt8(0)) { $0 &+ $1 })
        var frame: [UInt8] = [0x3E]
        for byte in body {
            switch byte {
            case 0x3C: frame.append(contentsOf: [0x3D, 0x2C])
            case 0x3D: frame.append(contentsOf: [0x3D, 0x2D])
            case 0x3E: frame.append(contentsOf: [0x3D, 0x2E])
            default: frame.append(byte)
            }
        }
        frame.append(0x3C)
        return frame
    }

    private func hex(_ byte: UInt8) -> String {
        String(format: "%02X", byte)
    }

    private func addTrace(_ line: String) {
        if trace.count < 80 { trace.append(line) }
    }

    private func closeSession() {
        generation += 1
        for stream in [session?.inputStream as Stream?, session?.outputStream as Stream?].compactMap({ $0 }) {
            stream.close()
            stream.remove(from: .main, forMode: .common)
            stream.delegate = nil
        }
        session = nil
        pending.removeAll()
        probing = false
    }

    deinit {
        session?.inputStream?.close()
        session?.outputStream?.close()
    }
}
