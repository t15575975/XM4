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

## 已確認：LiveContainer 安裝方式不支援客體 App 的 Widget

2026-11-11 使用者將 XM4Control 0.2.0 放進 **LiveContainer**，可開啟 App，但在 iOS「捷徑」與「加入小工具」都找不到 XM4Control。

這是已知的安裝平台限制，而不是應用程式自己開啟失敗。LiveContainer 官方 [README](https://github.com/LiveContainer/LiveContainer#compatibility) 明言 guest app extensions 無法在 SpringBoard 註冊，因為客體 App 並非由系統安裝且缺少附加 App ID。故 WidgetKit extension 和客體專屬 App Intents 都不能依靠 LiveContainer 進行一般系統註冊。

- **解決方向**：需將 XM4Control 視為 iOS 原生 App **直接側載／系統安裝**，而不是在 LiveContainer「加入 IPA」。使用 Windows 和免費 Apple ID 的 Sideloadly、SideStore／AltStore 等原生側載流程；確認 **保留並重新簽署**主 App 和 `PlugIns/XM4StatusWidget.appex`。
- 實際安裝若移除 `.appex`，主 App 可能能開，但小工具必然消失。
- 免費 Apple ID 對同時啟用 App 數與 App IDs 有限制；Widget 會額外消耗至少一個 App ID，不能假定一定有剩餘額度。先確認剩餘配額，**不自動移除目前的 LiveContainer**。
- 如果只是想從 iOS「捷徑」**啟動** LiveContainer 內的 XM4Control，LiveContainer 自身可能提供 Launch App 捷徑；那是啟動客體 App，**不等於把 XM4Control 的 App Intents／Widget 註冊到系統**，更無法繞過 iOS Sony RFCOMM 控制權限。
- 直接側載也不是保證所有功能正常：需要在實機確認 Widget 可選取、捷徑動作被索引。CI log 中 `appintentsnltrainingprocessor` 曾顯示非致命的 SSU 訓練資料解析警告，尚待實機驗證捷徑搜尋結果。
- LiveContainer 現有客體應用程式資料不會自動搬到新安裝的原生 App。

官方參考：[LiveContainer 官方 README](https://github.com/LiveContainer/LiveContainer)、[LiveContainer Add to Home Screen 指南](https://livecontainer.github.io/docs/guides/add-to-home-screen)、[Sideloadly Windows 免費 Apple ID 說明](https://sideloadly.io/)。

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
