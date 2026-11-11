# XM4Control — v1.2.0 Handoff / 接手文件

**Last verified:** 2026-11-11 (Asia/Taipei)
**Repository:** https://github.com/t15575975/XM4
**Release target:** `v1.2.0` / `1.2.0`
**Release source before handoff:** `main` at `0ea4119761e1981a6a05feda87ed780ac804241e`
**Stable rollback branch:** `release/v1.0.0` at `b10de6431d51d7c4a679eb6477376aa8c91028b9`
**Environment:** Windows 10 development host, GitHub Actions `macos-15` Xcode builder, iPhone 16 Pro Max, Sony **WF-1000XM4** firmware **2.3.1**, no Mac/no extra hardware, personal Apple ID.
**Primary objective:** Direct iOS Action Button/Shortcuts **ANC → AMBIENT → OFF → ANC**, no Sony Sound Connect UI, no additional Bluetooth relay; Home Screen Widget adds *direct* ANC/AMBIENT/OFF selection, connected-only controls, and battery.

## Executive summary / bottom line

The former iOS RFCOMM limitation was overcome through **Apple ExternalAccessory** and the real Sony `jp.co.sony.songpal.mdr.link2` protocol, found via Sonitus. The owner physically tested a **stock/non-jailbroken iPhone**, reporting a working three-mode shortcut / Action Button flow (user confirmation). A detailed shared trace independently demonstrates **ANC → AMBIENT** with Sony ACK and successful post-write `67 15` readback. Do **not** claim all three iPhone transitions are individually documented by traces; Windows verified all three.

The **v1.0.0 stable version** is frozen in `release/v1.0.0`. **v1.2.0** adds a WidgetKit control panel with three direct-mode App Intents, a Sony V2 battery probe for left/right/case, and a connection-gated display. CI confirmed that the iOS app and embedded Widget extension build and package; **battery responses and widget button execution are not yet physically verified on the iPhone**. This is the highest-priority unresolved work. Release 1.2.0 should carry this qualification.

## Confirmed vs not yet confirmed

| Capability | State | Evidence / caveat |
|---|---|---|
| Windows Sony Bluetooth Classic RFCOMM 9 transport | **Hardware verified** | [Windows evidence](windows-rfcomm-validation.md) |
| Windows three-mode cycle ANC → AMBIENT → OFF | **Hardware verified** | Sony SET ACK + real `67 15` readback |
| iOS `EAAccessoryManager` detects Sony WF-1000XM4 | **Physical iPhone confirmed** | `Sony's Headphones`, connected `true`, `mdr.link2` |
| iOS `EASession` streams | **Physical iPhone confirmed** | input/output `NSStreamStatus(rawValue: 2)`; no errors |
| iOS Sony ANC GET `66 15` → `67 15` | **Physical iPhone confirmed** | AMBIENT level 20 reply |
| iOS ANC → AMBIENT SET + ACK + readback | **Physical iPhone confirmed** | See exact trace below |
| iOS Shortcut / Action Button three-mode cycle | **Owner reported fully working** | Individual reverse transitions not separately transcribed |
| v1.2 Widget direct ANC/AMBIENT/OFF buttons | **Implemented and CI-built, iPhone test pending** | Widget AppIntent generally executes in extension process |
| v1.2 Widget battery L/R/case | **Implemented and CI-built, iPhone test pending** | Sony V2 commands grounded in upstream source, exact WF-1000XM4 replies unknown |
| Hide Widget buttons when disconnected | **Implemented and CI-built, dynamic behavior unverified** | Timeline snapshots are **not immediate** |
| Signed, directly installable release IPA | **Not provided** | CI outputs **unsigned IPA**; signer must sign main app and Widget extension |

## User-supplied iPhone protocol evidence (2026-11-11)

First confirmed GET:
```
ExternalAccessory 可見裝置：1
名稱：Sony's Headphones
製造商：Sony
型號：WF-1000XM4
連線狀態：true
協定：com.amazon.btecho, jp.co.sony.songpal.mc.link2,
       com.amazon.btfor3p, com.amazon.btalexa,
       jp.co.sony.songpal.mdr.link2
Protocol: jp.co.sony.songpal.mdr.link2; action: GET ANC only
Stream opened
Stream opened
TX: ANC GET 66 15
RX type=01 seq=1 payload=
RX type=0C seq=1 payload=67 15 01 01 01 02 00 14
```

Then successful mode change:
```
Protocol: jp.co.sony.songpal.mdr.link2; action: ONE cycle with readback
Stream opened
Stream opened
TX: ANC GET 66 15
RX type=01 seq=1 payload=
RX type=0C seq=1 payload=67 15 01 01 00 02 00 14
BEFORE ANC; SET AMBIENT; wind=2 voice=0 level=20
RX type=01 seq=0 payload=
SET ACK; querying independent readback
TX: ANC GET 66 15 (readback)
RX type=0C seq=0 payload=69 15 01 01 01 02 00 14
RX type=01 seq=1 payload=
RX type=0C seq=1 payload=67 15 01 01 01 02 00 14
VERIFIED mode=AMBIENT
Stream end: input=NSStreamStatus(rawValue: 2) output=NSStreamStatus(rawValue: 2)
```

**Decode:** `67 15 01 [enabled] [ambientFlag] [wind] [voice] [level]`; mode ANC = enabled 1 / ambient 0, AMBIENT = enabled 1 / ambient 1, OFF = enabled 0. The SET opcode is `68 15`. The driver preserves wind/voice/level on SET, reads mode before writing, and only reports verified change if independent readback matches the requested target. **Never retry a failed SET automatically**: a write may have succeeded without an observed reply.

## iOS application architecture and files

| File | Role |
|---|---|
| `XM4Control/Bluetooth/SonyEAProbe.swift` | Sony ExternalAccessory session, V2 framed protocol parser/encoder, read-current ANC, once-only cycle and direct setMode; async completion for Shortcut/Widget intents |
| `XM4Control/App/XM4Shortcuts.swift` | `CheckXM4AudioRouteIntent`, `CycleXM4ModeIntent`, AppShortcutsProvider; `openAppWhenRun=false` |
| `XM4Control/Shared/XM4SetModeIntent.swift` | `XM4ModeSelection` + exact-mode `XM4SetModeIntent` for ANC, AMBIENT, OFF; linked to both app and Widget extension |
| `XM4Control/App/ContentView.swift` | Audio-route diagnostics, BLE diagnostics, Sony EA discovery/GET, manual cycle and exact-mode test buttons, copyable traces |
| `XM4Control/Widget/XM4StatusWidget.swift` | Widget timeline and UI; three direct-mode buttons visible only when current snapshot says connected |
| `XM4Control/Widget/XM4BatteryReader.swift` | Isolated Sony V2 battery read on Widget timeline, parses left/right/case; ranges checked and unknown values shown as `--` |
| `XM4Control/Shared/XM4AudioRoute.swift` | Snapshot of iPhone audio output route; **not** pairing status or live Sony ANC state |
| `XM4Control/Info.plist` | Sony accessory protocol declarations, app version and Bluetooth usage |
| `XM4Control/Widget/Info.plist` | Widget extension Sony accessory protocol declarations and version |
| `XM4Control.xcodeproj/project.pbxproj` | App + Widget source membership, iOS versions and packaging |
| `.github/workflows/ios-build.yml` | macOS runner builds and packages unsigned IPA + Widget, uploads artifact (14-day retention) |
| `tools/XM4SdpProbe/` | Windows .NET RFCOMM reading, writing and wire codec; valuable independent cross-check |
| `docs/windows-rfcomm-validation.md` | Original Windows proof, packets and observations |
| `docs/ios-externalaccessory-probe.md` | iPhone EA session / GET / SET proof, constraints |
| `docs/RELEASES.md` | Version evolution and rollback baseline |

All code and engineering handoff remain in the GitHub repository (not duplicated in a separate knowledge database).

## v1.2.0 Widget behavior and limits

- **Connected gate:** `EAAccessoryManager.shared().connectedAccessories` must contain a connected item with `modelNumber == "WF-1000XM4"` and protocol `jp.co.sony.songpal.mdr.link2`. This is more specific than iPhone audio-output route; if disconnected the three buttons are omitted.
- **Widget timeline:** reads a connection snapshot when WidgetKit asks for one. A preferred refresh after **15 minutes** is *not* an iOS guarantee. After an unplug/disconnection the existing rendered snapshot may remain temporarily. An attempted mode action additionally verifies the connected Sony accessory and should fail rather than blindly write.
- **Battery:** Sony V2 `22 09` → `23 09 [L][Lchg][R][Rchg]`; `22 0A` → `23 0A [case][chg]`. Unknown values/invalid percentages show `--`. The Widget does **not** fabricate live battery data or rely on iPhone battery percent.
- **Data freshness:** battery figures reflect **last successful Widget timeline query**, not continuous telemetry; the widget shows the time of the snapshot.
- **Widget direct mode:** three Button(intent:) controls call an AppIntent in the Widget extension. It reads the actual current ANC mode, checks target, sends SET at most once, verifies via GET; a no-op already-in-target response is valid success. **Extension execution may differ from the known working App process**; verify with actual device.
- **Compatibility:** iOS app deployment target 16.0, widget target 17.0; small and medium widgets; no extra MFi hardware, no App Groups assumed. Experimental ExternalAccessory operation from a Widget extension remains a risk.

## Build, delivery and installation

- GitHub Actions workflow: [iOS build](https://github.com/t15575975/XM4/actions/workflows/ios-build.yml), macos-15 runner.
- Latest **pre-handoff** successful build on `main`: [run 42947410530](https://github.com/t15575975/XM4/actions/runs/42947410530), source commit `0ea4119761e1981a6a05feda87ed780ac804241e`. The workflow packages `XM4Control-unsigned.ipa` in artifact `XM4Control-unsigned-ipa`.
- The CI IPA is **unsigned**. It cannot be installed as-is. Use a suitable iPhone signing method on Windows. The nested `XM4StatusWidget.appex` must also be signed correctly; free Apple ID provisioning may expire.
- Signed IPA (if user produces one) and any certificates/secrets are **not in GitHub**. Never commit Apple signing material.
- On rollback, use the frozen [release/v1.0.0](https://github.com/t15575975/XM4/tree/release/v1.0.0) rather than rewriting working protocol code.

## Immediate handoff tasks, prioritized

1. **Install release 1.2.0 unsigned IPA after signing** (app + extension). On a stationary, unlocked iPhone with both earbuds connected, add **XM4 三模式控制** small/medium Widget.
2. **Verify battery replies**. Check L / R / case vs Sony Sound Connect. If blank, capture trace in dedicated diagnostic mode, and determine if `22 09` reply is delivered and whether `22 0A` is supported. Do not assume an available earbud is charging when reading `--`. Check battery power-state responses individually and timeout fallback.
3. **Verify direct Widget actions** ANC, AMBIENT, OFF independently and on different target states. If Widget cannot open Sony EA, compare equivalent direct mode buttons **inside the App** to locate the extension/process limit. Do not falsely report success.
4. **Verify disconnected UI**: put earbuds in the case, disconnect, and observe widget refresh timing; test reconnect. If delay is objectionable, investigate lifecycle-triggered reload within Apple's restrictions. Do not promise instantaneous hide.
5. **Verify app buttons / Shortcut regression** after 1.2.0 packaging. If the Widget affects stable controls, preserve v1.0.0 branch and fix only the development branch.
6. **Improve observability and reliability** after real traces: centralize battery and ANC sessions if concurrency conflicts occur; check multiple taps, App Intent runtime limits, duplicate EASessions, stream timeouts and disconnected behavior; prefer strict decoding to guessed values.
7. **Release process:** maintain a GitHub Release titled `XM4Control 1.2.0`, notes pointing at this handoff, and attach an **unsigned** IPA clearly labeled as requiring user signing. Release tag should freeze a known commit; do not silently move it later.

## Known risks / unresolved issues

- **Release 1.2.0 is NOT proof the Widget runs end-to-end.** Compiling and archiving differs from real ExternalAccessory use inside WidgetKit.
- **Widget connection is snapshot-based**, so a disconnected headset may still have visible controls until refresh. Actual action needs real-time connection checking.
- **Battery response layouts are referenced from [sony-device-center V2](https://github.com/marconvcm/sony-device-center/blob/main/libs/sony-protocol/src/ProtocolV2.cpp)**, but the user's WF-1000XM4 left/right/case responses have not yet been captured.
- **No precise current ANC mode badge is shown on the Widget**; avoid presenting a last-tapped target as current truth.
- **iOS 17 widget-target restriction:** `ForegroundContinuableIntent` produced compile error `unavailable in application extensions for iOS`. We reverted to standard `AppIntent`. Do not reintroduce `ForegroundContinuableIntent` in shared extension code.
- **ExternalAccessory MFi/protocol availability cannot be generalized to other Sony models** from one user device result.
- **Multiple rapid widget taps may initiate conflicting sessions** across processes; do not auto-retry or assume a global lock.
- **Physical safety:** test while stationary; do not manipulate phone/UI while riding.
- **Honesty rule for handoff:** user reported overall app/shortcut success; independent copied iPhone trace explicitly proves ANC → AMBIENT. Preserve both claims at their respective evidence levels.

## Primary references

- Sonitus iOS Sony ExternalAccessory implementation: https://github.com/semvis123/Sonitus
- Sony Device Center V2 source (battery queries / ANC): https://github.com/marconvcm/sony-device-center/blob/main/libs/sony-protocol/src/ProtocolV2.cpp
- Protocol and Windows validation: [windows-rfcomm-validation.md](windows-rfcomm-validation.md)
- iPhone transport and readback traces: [ios-externalaccessory-probe.md](ios-externalaccessory-probe.md)
- Version history: [RELEASES.md](RELEASES.md)

**Next agent:** start by comparing this document with the latest `main` HEAD and GitHub Actions; do not overwrite `release/v1.0.0`. Keep evidence and uncertain device behavior separate.
