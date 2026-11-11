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
