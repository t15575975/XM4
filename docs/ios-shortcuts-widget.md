# iOS 捷徑與 Widget（研究版 0.2.0）

更新：2026-11-11。這份文件記錄已提交的程式與尚未實測的裝置行為。

## 已在 Windows 實機完成的三模式循環

Sony WF-1000XM4（韌體 2.3.1）的 RFCOMM Channel 9、Sony V2 `66 15` / `67 15` 狀態查詢及 `68 15` 模式設定已確認。2026-11-11 使用 `dotnet run -- --cycle` 成功完成：

1. OFF → ANC
2. ANC → AMBIENT
3. AMBIENT → OFF

每次均有耳機 ACK，以及另一筆 Sony `67 15` 查詢確認新狀態。詳見 [Windows 驗證](windows-rfcomm-validation.md)。

## iPhone 現有能力

### 捷徑（App Intents）

App 編譯時向 Shortcuts 提供：

- **檢查 XM4 音訊連線**：讀取 `AVAudioSession.sharedInstance().currentRoute.outputs`。只有音訊路由實際選到 WF-1000XM4（A2DP/HFP）才回報「正在輸出音訊」。若未選到，只說明「目前未作為音訊輸出」，**不可推論藍牙已斷開**。
- **XM4 三模式循環（iOS 控制待解鎖）**：目前會回報明確的 Unsupported Error，**不會切換耳機模式**。這是 App Intent 入口，待找到可透過 iOS 公開 API 使用的 Sony 控制傳輸後接上已驗證的三段控制邏輯。

裝入 iPhone 後，先開啟 XM4Control 一次，再於「捷徑」→ 新增動作 → 搜尋 `XM4Control`。若還沒有出現，確認應用程式安裝版本為 0.2.0、重新開啟 app 與捷徑 App；如有裝置端或重新簽署問題，保留安裝日誌。

**動作按鈕目標**：最終三模式 App Intent 經實機驗證後，可在 iPhone 設定 → 動作按鈕 → 捷徑中選取。現在不應指派它作騎車模式切換，因為尚無 iOS 控制傳輸。

### 小工具（WidgetKit）

Widget target 為 `XM4StatusWidget.appex`，提供主畫面小型／中型 Widget。

- 顯示目前 iPhone 音訊輸出是否為 XM4，及檢查時間。
- 在 Widget 上顯示「未作為音訊輸出」**不代表**未配對、未連線或藍牙斷線。
- Widget extension 不是長駐程式，不會持續監聽 Classic Bluetooth；系統決定更新頻率，不保證立即反映音訊路由變動。
- 首次安裝後應至少開啟一次 XM4Control，再於主畫面長按 → 加入 Widget → 搜尋 XM4Control。

### BLE 探索與連線

App 內另顯示 BLE 掃描是否看到 `WF-1000XM4` 廣播，及是否有 App 自身建立的 GATT 連線。這是 **BLE 狀態**，不等於 iOS 的 Classic 音訊藍牙連線，也不等於 Sony ANC 控制通道。

## Windows + 免費 Apple ID 側載

GitHub Actions 的 iOS workflow 於 macOS runner 使用 Xcode 編譯 `XM4Control.app` 和嵌入的 `PlugIns/XM4StatusWidget.appex`，再提供未簽署 IPA。

- 目前沒有 App Groups entitlement：避免為現階段的唯讀 Widget 增加額外 provisioning 要求。
- 未簽署 IPA **不能直接安裝**，須經既有 Windows 側載／簽署工具重新簽署主 App 與 `.appex`，且簽章及 bundle ID 關係要正確。
- 免費 Apple ID 的個人開發簽署期限等限制會影響安裝與後續重新簽署。
- CI 成功只能證明能編譯、封裝；**無法證明 iPhone 上捷徑可被搜尋、Widget 可新增、音訊路由觀察一定與實際狀態一致**。這些必須實機測試。

## 為什麼 Windows 能切換、iOS 尚不能

Windows 測試是 Windows Winsock2 Bluetooth Classic RFCOMM 對 Channel 9 連線。iOS CoreBluetooth 沒有提供第三方 App 的等效通用 RFCOMM socket。Apple ExternalAccessory 框架支援特定 MFi 配件協定，不代表 WF-1000XM4 的 Sony 專有 Channel 9 能由任意 App 開啟。

不能以 Windows 通過作為 iOS 端模式切換已可用的證明。後續若研究出獲允許且可靠的 iOS 傳輸，再把 `CycleXM4ModeIntent.perform()` 連到實際控制，並讓 Widget 顯示經驗證的裝置模式；在此之前保留清楚的不支援狀態。

來源：Apple [App Intents](https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework)、[WidgetKit](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)、[AVAudioSession.currentRoute](https://developer.apple.com/documentation/avfaudio/avaudiosession/currentroute)、[External Accessory](https://developer.apple.com/documentation/externalaccessory)、[個人帳號限制](https://developer.apple.com/help/account/basics/about-your-developer-account)。
