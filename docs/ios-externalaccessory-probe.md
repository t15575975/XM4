# iOS ExternalAccessory diagnostic (read-only)

## Why

Sonitus (https://github.com/semvis123/Sonitus) uses Apple's `ExternalAccessory` framework and Sony accessory protocols `jp.co.sony.songpal.mdr.link` / `jp.co.sony.songpal.mdr.link2` on jailbroken iOS. Its existence **does not prove** those protocols can be accessed by a normal sideloaded app or that Apple MFi approval can be bypassed.

## What was added

- `XM4Control/Bluetooth/SonyEAProbe.swift` enumerates `EAAccessoryManager.shared().connectedAccessories` and each accessory's `protocolStrings`.
- The iOS app includes both Sony protocol IDs under `UISupportedExternalAccessoryProtocols`.
- A separate, explicit button calls `EASession(accessory:forProtocol:)`, opens input/output streams, waits two seconds, captures stream statuses/errors and closes them. **It does not write any bytes.**
- The existing Shortcuts three-mode action remains intentionally unavailable unless a working, authorized iOS transport is independently proven.

## On-device test

1. Install the newest correctly signed build on the iPhone; the GitHub Actions artifact is unsigned and cannot be directly installed.
2. Pair/connect the WF-1000XM4 to the iPhone, then open XM4Control.
3. Under **Sony ExternalAccessory 診斷**, tap **重新搜尋 ExternalAccessory**.
4. Tap **複製 EA 診斷結果** and record what is shown.
5. Only if a Sony accessory protocol is present, tap **測試 Sony EASession 開啟**; wait for the stream statuses, then copy the result.
6. Do not interpret accessory visibility, an EASession object, or a stream with `open` status as confirmed ability to control ANC. Command/response verification is a separate later step.

## Limits / safety

- A device may be paired and connected for Bluetooth audio yet not appear in `connectedAccessories`.
- Ordinary third-party apps may be restricted from Sony's MFi protocol; listing the protocol identifiers in Info.plist does not grant authorization.
- No outbound Sony commands are issued; this is a diagnostic only.
- Do not use the iPhone or touch controls while riding.

## 2026-11-11 confirmed iPhone test

The user reported a real, stock iPhone run with:
- `Sony's Headphones` / manufacturer Sony / model `WF-1000XM4` / connected=true.
- `jp.co.sony.songpal.mdr.link2` among the available protocols.
- `EASession` input and output both `NSStreamStatus(rawValue: 2)` (open); neither stream reported an error.

This establishes actual app-side Sony EASession availability on this device, **not yet Sony command/response success**.

## New optional read-only Sony V2 GET test

The app now offers **讀取 XM4 目前 ANC 模式（不切換）**. It opens the same EASession, writes a Sony V2 `DATA_MDR` GET `66 15` frame, processes inbound Sony frames and protocol ACKs, and attempts to decode a valid `67 15` mode response (ANC / AMBIENT / OFF). It transmits **no** ANC `68 15` SET command.

When connected, press the button only while stationary, then copy the ExternalAccessory diagnostic result including RX/TX trace. Verify a real `67 15` response before implementing a mode-setting action or Action Button shortcut. An open stream alone is insufficient evidence of control.

## 2026-11-11 iPhone GET command confirmed

Physical iPhone result from WF-1000XM4:

```
Protocol: jp.co.sony.songpal.mdr.link2; action: GET ANC only
TX: ANC GET 66 15
RX type=01 seq=1 payload=
RX type=0C seq=1 payload=67 15 01 01 01 02 00 14
```

The decoded state is **AMBIENT**, level **20**, wind byte **02**, voice **00**. The two streams were open and no stream errors were reported. This is validated command/response traffic on non-jailbroken iPhone.

## Manual one-step cycle test — experimental, not yet iPhone verified

The app includes an explicit button **手動切換 XM4 下一模式（實際變更耳機）**. This is a real mode-changing action, not a passive diagnostic.

- Read a valid `67 15` current state; abort if missing/invalid.
- Determine exactly one next mode: ANC → AMBIENT → OFF → ANC.
- Send one `68 15` with preserved wind, voice and ambient level, based on prior Windows hardware-verified behavior.
- Wait for Sony ACK; query `66 15` again; only report success if `67 15` readback matches target.
- Never automatically retry SET. If timeout occurs, the device may have changed mode even without a successful readback.
- The existing Shortcut App Intent is **still disabled** pending actual on-device SET and readback verification. No automatic cycling while riding.

Perform the first manual SET test only while stationary. Copy the complete trace including before, SET, ACK, and after. The on-device mode change has **not yet been verified**, despite confirmed iOS GET access.

## 2026-11-11 stock iPhone mode change confirmed (ANC to AMBIENT)

User-supplied real-device trace:

```
TX: ANC GET 66 15
RX type=0C seq=1 payload=67 15 01 01 00 02 00 14
BEFORE ANC; SET AMBIENT; wind=2 voice=0 level=20
RX type=01 seq=0 payload=
SET ACK; querying independent readback
TX: ANC GET 66 15 (readback)
RX type=0C seq=0 payload=69 15 01 01 01 02 00 14
RX type=0C seq=1 payload=67 15 01 01 01 02 00 14
VERIFIED mode=AMBIENT
```

This independently confirms **ANC → AMBIENT** via stock iPhone, not merely protocol visibility. The opposite direction and OFF transitions remain to be checked on the iPhone.

## Shortcut / Action Button implementation (device verification pending)

The app's `CycleXM4ModeIntent` now invokes `SonyEAProbe.shared.cycleOnce` with an asynchronous completion callback. It only returns success if a subsequent `67 15` matches the target state. On failed transmission, stream errors, timeout, or an unexpected state, it returns an error and does not retry the SET command.

The intent declares `openAppWhenRun = false`, but that **does not yet prove** the iOS system can keep the ExternalAccessory session alive while running via Shortcuts or the Action Button, or that the action works while the phone is locked. Test while stationary, first with the phone unlocked. When iOS presents a stale shortcut label, delete and add the action again after installing the latest signed build.

Do not claim all three physical transitions are proven based on this one successful ANC → AMBIENT trace.
