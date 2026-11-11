# XM4Control

Experimental iOS companion project for Sony WF-1000XM4.

## Current status (2026-11-11)

**Windows Sony ANC control confirmed on physical WF-1000XM4 firmware 2.3.1.** The native Winsock2 tool connected via Bluetooth Classic RFCOMM channel 9, read the Sony V2 `67 15` status, sent `68 15 01 00 00 02 00 14`, received an ACK, and read back **OFF**. The wearer separately confirmed that ANC/environmental processing truly switched off. The previously active mode was AMBIENT level 20.

- `--native-read-anc`: read the real current ANC mode, no setting change (verified).
- `--set-off`: set OFF with read-before-write / readback verification (verified from AMBIENT).
- `--set-anc`, `--set-ambient`, `--cycle`: **all three --cycle transitions hardware-verified** on 2026-11-11 with Sony ACK and post-write readback: OFF → ANC → AMBIENT → OFF.
- [Windows validation log and source evidence](docs/windows-rfcomm-validation.md).

From a Windows checkout in `tools/XM4SdpProbe`, use `dotnet run -- --cycle` for one step in the requested **ANC → AMBIENT → OFF → ANC** sequence; every command reads the current mode before setting and verifies the result. Test only while stationary.

**iPhone Sony ExternalAccessory ANC control is now physically validated for ANC → AMBIENT.** The stock iPhone opened `jp.co.sony.songpal.mdr.link2`, sent `66 15`, received `67 15`, sent one `68 15` SET, got a protocol ACK, and independently read back AMBIENT. This is direct communication without a Windows relay. The other iOS mode transitions and background App Intents/Action Button execution are not yet physically verified.

## iOS Shortcuts and Home Screen Widget (research build)

The iOS app now contains native **App Intents** for Shortcuts and a separately bundled **WidgetKit** extension.

- **Shortcut: Check XM4 audio output** — functional passive check of the iPhone's current `AVAudioSession` output route, not a full Bluetooth pairing-status API.
- **Shortcut: XM4 3-mode cycle** — newly connected to the real Sony ExternalAccessory session with one-shot read/SET/readback verification. App Intent execution without opening the app and Action Button operation still require physical iPhone testing. Failure cannot be interpreted as proof no setting changed; it never automatically retries.
- **Home Screen Widget: XM4 audio status** — shows whether the current iPhone audio output route appears to be WF-1000XM4, plus the check time. A negative result means **not selected as the current audio output**, not necessarily Bluetooth-disconnected. WidgetKit refresh is system-scheduled rather than real-time.
- **App screen:** Shows audio route, BLE/GATT diagnostic, Sony ExternalAccessory discovery, true ANC state GET, and manually tested ANC cycling.

For compatibility with Windows-based unsigned IPA signing using a free Apple ID, the Widget currently uses a direct route snapshot and does **not** require App Groups or shared entitlements. Native WidgetKit and App Intents metadata are built into the unsigned IPA, but user installation, re-signing of the `.appex`, Shortcuts appearance and on-device Widget behavior still require device verification.

[Shortcuts and Widget usage / limitations](docs/ios-shortcuts-widget.md).

## Requirements

- Windows PC for editing and Git operations.
- GitHub account.
- GitHub Actions macOS runner to compile the iOS target.
- Xcode project signing / installation still requires a valid signing identity. A free Apple ID can generally be used for personal-device development with short-lived provisioning; an unsigned CI artifact alone cannot be installed.
- iPhone paired with the WF-1000XM4 and Bluetooth enabled.

## Build

1. Create a GitHub repository named `XM4Control`.
2. Upload this project.
3. Enable GitHub Actions.
4. Run the `iOS build (unsigned research artifact)` workflow.
5. Download the artifact. It is an unsigned build for inspection only; it is not yet a directly installable IPA.

## Safety / privacy

No Apple ID credentials, certificates, provisioning profiles, or device identifiers should be committed to this repository.
