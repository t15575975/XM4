import AppIntents

/// This shortcut is functional. It reports iOS's *active audio output route*,
/// not an unobservable general Bluetooth Classic pairing/connection state.
struct CheckXM4AudioRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "檢查 XM4 音訊連線"
    static var description = IntentDescription(
        "檢查 WF-1000XM4 是否正在作為 iPhone 的音訊輸出；不能確認一般藍牙配對狀態。"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: XM4AudioRoute.snapshot().shortcutsResult)
    }
}

/// The action is intentionally exposed so it can be selected in Shortcuts
/// when a supported iOS ANC transport exists. Today it fails explicitly
/// rather than pretending to control Sony's RFCOMM channel from CoreBluetooth.
struct CycleXM4ModeIntent: AppIntent {
    static var title: LocalizedStringResource = "XM4 三模式循環（iOS 控制待解鎖）"
    static var description = IntentDescription(
        "目標：ANC → 環境音 → 關閉；目前 iOS 尚沒有已驗證的 Sony RFCOMM 控制通道。"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard XM4IOSControlTransport.isAvailable else {
            throw XM4ShortcutError.noSupportedControlTransport
        }
        return .result()
    }
}

enum XM4IOSControlTransport {
    /// Do not enable until a real, validated and shippable iOS transport exists.
    static var isAvailable: Bool { false }
}

enum XM4ShortcutError: LocalizedError {
    case noSupportedControlTransport

    var errorDescription: String? {
        switch self {
        case .noSupportedControlTransport:
            return "尚無可用的 iOS Sony ANC 傳輸通道。Windows 的 RFCOMM Channel 9 控制已驗證，但 iOS 公開 CoreBluetooth API 無法直接呼叫該 RFCOMM Socket；捷徑未改變耳機模式。"
        }
    }
}

struct XM4AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: CheckXM4AudioRouteIntent(),
                phrases: ["Check \(.applicationName) audio output"],
                shortTitle: "XM4 音訊狀態",
                systemImageName: "headphones"
            ),
            AppShortcut(
                intent: CycleXM4ModeIntent(),
                phrases: ["Cycle \(.applicationName) noise control"],
                shortTitle: "XM4 三模式（尚未支援）",
                systemImageName: "arrow.triangle.2.circlepath"
            )
        ]
    }
}
