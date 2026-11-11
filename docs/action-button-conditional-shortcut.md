# iPhone Action Button — XM4 if connected, otherwise toggle Silent Mode

**Applies to:** development build after v1.2.0, adding the App Intent **檢查 XM4 是否已連線**.
**Stable v1.2.0 release:** unchanged. New unsigned IPA must be signed and installed to expose this added action.

## Required iOS Shortcuts setup

1. Open **捷徑**, tap **+**, name the new shortcut **XM4／靜音智慧切換**.
2. Add the **XM4Control → 檢查 XM4 是否已連線** action. It returns a **Boolean**, checking `EAAccessoryManager.connectedAccessories`, `WF-1000XM4`, `mdr.link2`, and `isConnected`; it does **not** rely on the currently selected audio output.
3. Add **如果 (If)**. Select the previous action's **Boolean** result; condition **是 (true)**.
4. In the true branch add **XM4Control → XM4 三模式循環**.
5. In **否則 (Otherwise)** add iOS Shortcuts' **設定靜音模式 / Set Silent Mode** action and change **開啟 (Turn On)** to **切換 (Toggle)**. Otherwise the action would always force silence on.
6. Close **結束如果 (End If)**; save shortcut.
7. Set **設定 → 動作按鈕 → 捷徑 → XM4／靜音智慧切換**. iPhone requires **press and hold** (not a mere short click).

Expected behavior:
- Sony WF-1000XM4 is available through ExternalAccessory: one ANC → AMBIENT → OFF → ANC step. Read-current → send one SET → readback.
- No matching Sony accessory: toggle the phone's Silent Mode between Ring and Silent.
- If the headset disconnects between the Boolean check and the cycle command, that command can fail rather than automatically falling back to Silent Mode. This is an intentional race-condition safety behavior.
- If the earphones are paired/connected as audio but do not expose Sony EA momentarily, the condition returns false, and Silent Mode toggles. User should physically test this scenario before relying on it.
- The iOS action does not remove the stable standalone mode-cycle shortcut.

**Verification:** test both paths while stationary and unlocked, and verify the correct mode/actual silent icon. Test locked iPhone only after unlocked behavior succeeds.

**Sources:** [Apple Action Button guide](https://support.apple.com/guide/iphone/use-and-customize-the-action-button-iphe89d61d66/ios) and [project's confirmed EA protocol](ios-externalaccessory-probe.md).
