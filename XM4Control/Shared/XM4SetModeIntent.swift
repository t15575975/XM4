import Foundation
import AppIntents

/// Explicit mode buttons, shared by app and WidgetKit targets (iOS 17+).
/// The selected state is read from the headphones, not guessed from WidgetKit.
enum XM4ModeSelection: String, AppEnum {
    case anc = "ANC"
    case ambient = "AMBIENT"
    case off = "OFF"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "XM4 降噪模式"
    static var caseDisplayRepresentations: [XM4ModeSelection: DisplayRepresentation] = [
        .anc: "降噪",
        .ambient: "環境音",
        .off: "關閉"
    ]
}

// Route a WidgetKit button to the host-app process (iOS 17 compatible),
// where the Sony EASession transport has already been physically validated.
struct XM4SetModeIntent: ForegroundContinuableIntent {
    static var title: LocalizedStringResource = "設定 XM4 模式"
    static var description = IntentDescription("將 WF-1000XM4 設為指定的降噪模式；先讀取、只送一次 SET、再讀回驗證。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "模式")
    var mode: XM4ModeSelection

    init() {}

    init(mode: XM4ModeSelection) {
        self.mode = mode
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let desired = mode.rawValue
        let outcome: (Bool, String) = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                SonyEAProbe.shared.setMode(desired) { ok, message in
                    continuation.resume(returning: (ok, message))
                }
            }
        }
        guard outcome.0 else { throw XM4WidgetControlError.unverified(outcome.1) }
        return .result(value: outcome.1)
    }
}

enum XM4WidgetControlError: LocalizedError {
    case unverified(String)

    var errorDescription: String? {
        switch self {
        case .unverified(let text):
            return "耳機模式未確認：\(text)"
        }
    }
}
