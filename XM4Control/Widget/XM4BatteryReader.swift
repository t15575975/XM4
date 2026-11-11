import Foundation
import ExternalAccessory

struct XM4BatteryReading {
    let left: Int?
    let right: Int?
    let caseLevel: Int?

    static let unavailable = XM4BatteryReading(left: nil, right: nil, caseLevel: nil)
}

enum XM4AccessoryStatus {
    static func connected() -> Bool {
        EAAccessoryManager.shared().connectedAccessories.contains {
            $0.isConnected &&
            $0.modelNumber == "WF-1000XM4" &&
            $0.protocolStrings.contains("jp.co.sony.songpal.mdr.link2")
        }
    }
}

/// Non-mutating Sony V2 power-status probe, confined to the widget's timeline
/// callback. Sends 22 09 (L/R) and 22 0A (case), never a setting command.
/// Validity of values is checked. Missing replies yield nil, not made-up %.
final class XM4BatteryReader: NSObject, StreamDelegate {
    private var session: EASession?
    private var inputBuffer: [UInt8] = []
    private var outgoing: [UInt8] = []
    private var sequence: UInt8 = 0
    private var stage = 0
    private var left: Int?
    private var right: Int?
    private var caseLevel: Int?
    private var finishHandler: ((XM4BatteryReading) -> Void)?
    private var completed = false

    func read(completion: @escaping (XM4BatteryReading) -> Void) {
        guard !completed, finishHandler == nil else { completion(.unavailable); return }
        guard let accessory = EAAccessoryManager.shared().connectedAccessories.first(where: {
            $0.isConnected && $0.modelNumber == "WF-1000XM4" &&
            $0.protocolStrings.contains("jp.co.sony.songpal.mdr.link2")
        }), let opened = EASession(accessory: accessory, forProtocol: "jp.co.sony.songpal.mdr.link2"),
              let input = opened.inputStream, let output = opened.outputStream else {
            completion(.unavailable)
            return
        }
        session = opened
        finishHandler = completion
        for stream in [input as Stream, output as Stream] {
            stream.delegate = self
            stream.schedule(in: .main, forMode: .common)
            stream.open()
        }
        // The closure retains this probe while waiting for the real reply.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
            finish()
        }
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard !completed else { return }
        if eventCode.contains(.errorOccurred) || eventCode.contains(.endEncountered) {
            finish()
            return
        }
        if eventCode.contains(.openCompleted) || eventCode.contains(.hasSpaceAvailable) {
            if stage == 0, let output = session?.outputStream, output.hasSpaceAvailable {
                stage = 1
                sendQuery(0x09)
            }
            flush()
        }
        if eventCode.contains(.hasBytesAvailable) {
            readAvailable()
        }
    }

    private func sendQuery(_ subtype: UInt8) {
        enqueue(frame(type: 0x0C, seq: sequence, payload: [0x22, subtype]))
        sequence ^= 1
    }

    private func enqueue(_ bytes: [UInt8]) {
        outgoing.append(contentsOf: bytes)
        flush()
    }

    private func flush() {
        guard !completed, let stream = session?.outputStream,
              stream.hasSpaceAvailable, !outgoing.isEmpty else { return }
        let written = outgoing.withUnsafeBufferPointer { ptr in
            stream.write(ptr.baseAddress!, maxLength: ptr.count)
        }
        if written > 0 {
            outgoing.removeFirst(written)
        } else if written < 0 {
            finish()
        }
    }

    private func readAvailable() {
        guard let input = session?.inputStream else { return }
        var chunk = [UInt8](repeating: 0, count: 512)
        while input.hasBytesAvailable && !completed {
            let count = input.read(&chunk, maxLength: chunk.count)
            if count <= 0 { break }
            inputBuffer.append(contentsOf: chunk.prefix(count))
            if inputBuffer.count > 4096 { finish(); return }
            parse()
        }
    }

    private func parse() {
        while !completed {
            guard let start = inputBuffer.firstIndex(of: 0x3E) else {
                inputBuffer.removeAll()
                return
            }
            if start > 0 { inputBuffer.removeFirst(start) }
            guard let end = inputBuffer.dropFirst().firstIndex(of: 0x3C) else { return }
            let wire = Array(inputBuffer[1..<end])
            inputBuffer.removeFirst(end + 1)
            var body: [UInt8] = []
            var i = 0
            var valid = true
            while i < wire.count {
                if wire[i] == 0x3D {
                    i += 1
                    guard i < wire.count else { valid = false; break }
                    switch wire[i] {
                    case 0x2C: body.append(0x3C)
                    case 0x2D: body.append(0x3D)
                    case 0x2E: body.append(0x3E)
                    default: valid = false
                    }
                } else {
                    body.append(wire[i])
                }
                i += 1
            }
            guard valid, body.count >= 7 else { continue }
            let length = (UInt32(body[2]) << 24) | (UInt32(body[3]) << 16) |
                         (UInt32(body[4]) << 8) | UInt32(body[5])
            guard length <= 1024, body.count == Int(length) + 7 else { continue }
            let checksum = body.dropLast().reduce(UInt8(0)) { $0 &+ $1 }
            guard body.last == checksum else { continue }

            let type = body[0]
            let incomingSeq = body[1]
            let payload = Array(body[6..<(6 + Int(length))])
            if type == 0x01 && incomingSeq <= 1 {
                sequence = incomingSeq
            }
            if type == 0x0C {
                enqueue(frame(type: 0x01, seq: 1 &- (incomingSeq & 1), payload: []))
            }
            guard type == 0x0C, payload.count >= 4, payload[0] == 0x23 else { continue }
            if stage == 1 && payload[1] == 0x09 && payload.count >= 6 {
                left = payload[2] <= 100 ? Int(payload[2]) : nil
                right = payload[4] <= 100 ? Int(payload[4]) : nil
                stage = 2
                sendQuery(0x0A)
            } else if stage == 2 && payload[1] == 0x0A {
                caseLevel = payload[2] <= 100 ? Int(payload[2]) : nil
                finish()
            }
        }
    }

    private func frame(type: UInt8, seq: UInt8, payload: [UInt8]) -> [UInt8] {
        var body: [UInt8] = [type, seq, 0, 0, 0, UInt8(payload.count)]
        body.append(contentsOf: payload)
        body.append(body.reduce(UInt8(0)) { $0 &+ $1 })
        var result: [UInt8] = [0x3E]
        for byte in body {
            switch byte {
            case 0x3C: result.append(contentsOf: [0x3D, 0x2C])
            case 0x3D: result.append(contentsOf: [0x3D, 0x2D])
            case 0x3E: result.append(contentsOf: [0x3D, 0x2E])
            default: result.append(byte)
            }
        }
        result.append(0x3C)
        return result
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        let handler = finishHandler
        finishHandler = nil
        for stream in [session?.inputStream as Stream?, session?.outputStream as Stream?].compactMap({ $0 }) {
            stream.close()
            stream.remove(from: .main, forMode: .common)
            stream.delegate = nil
        }
        session = nil
        handler?(XM4BatteryReading(left: left, right: right, caseLevel: caseLevel))
    }
}
