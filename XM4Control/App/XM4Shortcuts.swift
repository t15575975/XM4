import Foundation
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

/// Calls the physical Sony ExternalAccessory transport. No simulated toggling:
/// the intent finishes successfully only after a matching 67 15 status readback.
struct CycleXM4ModeIntent: AppIntent {
    static var title: LocalizedStringResource = "XM4 三模式循環"
    static var description = IntentDescription(
        "直接控制 WF-1000XM4：ANC → 環境音 → 關閉。先讀取，再切換一次，讀回驗證；失敗不重試。"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let outcome: (Bool, String) = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                SonyEAProbe.shared.cycleOnce { verified, message in
                    continuation.resume(returning: (verified, message))
                }
            }
        }
        guard outcome.0 else {
            throw XM4ShortcutError.unverified(outcome.1)
        }
        return .result(value: outcome.1)
    }
}

enum XM4ShortcutError: LocalizedError {
    case unverified(String)

    var errorDescription: String? {
        switch self {
        case .unverified(let reason):
            return "XM4 切換未驗證：\(reason)"
        }
    }
}

struct XM4AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
                intent: CheckXM4AudioRouteIntent(),
                phrases: ["Check \(.applicationName) audio output"],
                shortTitle: "XM4 音訊狀態",
                systemImageName: "headphones"
        )
        AppShortcut(
                intent: CycleXM4ModeIntent(),
                phrases: ["Cycle \(.applicationName) noise control"],
                shortTitle: "XM4 三模式循環",
                systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
