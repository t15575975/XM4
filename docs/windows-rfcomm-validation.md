# WF-1000XM4 Windows RFCOMM validation

Status: **research-only; SDP confirmed; RFCOMM connection not yet confirmed** (2026-11-11).

## Actual user observations

- Windows 10.0.19045, .NET 9 runtime; WF-1000XM4 (firmware 2.3.1) paired and connected.
- Windows exposed A2DP, HFP, AVRCP; COM4/COM5 were not in the headset's PnP device container.
- Fresh SDP discovery returned 10 UUIDs, including `956c7b26-d49a-4ba8-b03f-b17d393cb6e2`.
- 32feet.NET connection to that UUID failed with `SocketErrorCode=InvalidArgument`, native WinSock error `10022` (`WSAEINVAL`). This is not evidence that ANC is unsupported.
- A later logging edit caused C# `CS0841` (use of local variable before declaration); fixed in commit `3882329`.

## Verified source-code findings (NOT claims of compatibility with this exact PC)

1. [Obito1903/sony-headphones-ctl](https://github.com/Obito1903/sony-headphones-ctl/blob/master/src/devices/wf1000xm4/mod.rs): WF-1000XM4-specific Rust code opens RFCOMM **channel 9** directly (Linux `bluer::rfcomm::SocketAddr`), and implements ANC / ambient / off; [ANC payload structure](https://github.com/Obito1903/sony-headphones-ctl/blob/master/src/devices/wf1000xm4/anc.rs).
2. [marconvcm/sony-device-center](https://github.com/marconvcm/sony-device-center/blob/main/Client/IBluetoothConnector.h): Sony V1 UUID `96cc203e-5068-46ad-b32d-e316f5e069ba` and Sony V2 UUID `956c7b26-d49a-4ba8-b03f-b17d393cb6e2`. [Windows connector](https://github.com/marconvcm/sony-device-center/blob/main/Client/windows/WindowsBluetoothConnector.cpp) uses native WinSock2 `SOCKADDR_BTH`, tries V1 then V2 with a fresh socket for the fallback.
3. [ibatra/sony-headphones-client](https://github.com/ibatra/sony-headphones-client/blob/main/src-tauri/src/bluetooth/windows.rs): Windows Rust connector uses native WinSock2, a 30-byte packed `SOCKADDR_BTH`, first connects by V1 UUID and then tries RFCOMM channels starting with **9**. Its README says Windows tested, but does not establish exact WF-1000XM4 firmware compatibility.

## Windows native connectivity probe

`tools/XM4SdpProbe/NativeRfcommProbe.cs` implements an independent WinSock2 check: socket family 32 / stream / protocol 3, a packed 30-byte `SOCKADDR_BTH`, and native error reporting. It sends **no application data**.

From repo root:

```powershell
git pull
cd tools\XM4SdpProbe
dotnet build
dotnet run -- --native-channel9
```

Optional independent comparison against UUID present in SDP:

```powershell
dotnet run -- --native-v2
```

Test only one method at a time. Closing a connection is the only intended side effect. Windows may need to reconnect audio afterward.

- `NATIVE CONNECTED`: transport connection only; does not prove Sony ANC protocol.
- `NATIVE CONNECT FAILED`: record WinSock code and selected service/channel; do not infer model-wide unsupported status.
- If both fail, examine Windows Bluetooth adapter compatibility and service channel assignment; do not blindly send commands to other UUIDs.
- Do not send arbitrary bytes to unverified services.

## iOS feasibility constraint

Passing these Windows tests will not grant a third-party iOS app general-purpose Bluetooth Classic RFCOMM access. iOS CoreBluetooth targets BLE. ExternalAccessory requires a supported accessory protocol. The iPhone-only, no-extra-hardware three-mode Action Button goal remains **unproven**; do not claim a working IPA until a valid on-device control path is shown.


## 2026-11-11: Transport milestone and read-only ANC interrogation

User ran `dotnet run -- --native-channel9` on Windows 10.0.19045 and got:

```text
Connect target: service=00000000-0000-0000-0000-000000000000, channel=9
NATIVE CONNECTED: Success. Closing without sending data.
```

This validates **RFCOMM channel 9 connection**, not Sony control-protocol behavior.

Source cross-check before attempting any ANC changes:
- [Sony Device Center ProtocolV2](https://github.com/marconvcm/sony-device-center/blob/main/libs/sony-protocol/src/ProtocolV2.cpp): WF-1000XM4 noise-control GET request `66 15`, status `67 15`. No write command needed for the current-mode query.
- [Sony Device Center NoiseControlCodec](https://github.com/marconvcm/sony-device-center/blob/main/libs/sony-protocol/src/NoiseControlCodec.h): strict layout `[67,15,01,enabled,ambient,wind,voice,level]`; enabled=0 is OFF, enabled=1 and ambient=0 is ANC, enabled=1 and ambient=1 is AMBIENT.
- [Sony Device Center FrameCodec](https://github.com/marconvcm/sony-device-center/blob/main/libs/sony-protocol/src/FrameCodec.cpp): `>`/ `<` framing, escaping 0x3c/0x3d/0x3e, 1-byte seq, 4-byte big-endian length, wrapped checksum.
- [Sony Device Center SonyProtocolSession](https://github.com/marconvcm/sony-device-center/blob/main/libs/sony-protocol/src/SonyProtocolSession.cpp): ACK received DATA_MDR with opposite sequence parity.

The optional `--native-read-anc` command sends **only the GET query `66 15`** plus required ACK frames to the established channel 9. This is a read-only state query, not a zero-byte probe; there can still be unexpected firmware behavior, so verify while stationary.

```powershell
cd F:\上傳作業區\XM4
git pull
cd tools\XM4SdpProbe
dotnet run -- --native-read-anc
```

Expected successful result: `ANC STATE CONFIRMED: OFF`, `ANC STATE CONFIRMED: ANC`, or `ANC STATE CONFIRMED: AMBIENT`, based on a valid 8-byte `67 15` response. This has **not yet been tested on the user's earbuds**.

Offline transport codec tests are run by Windows CI and can be run using `dotnet run -- --self-test`. **Do not proceed to ANC writes before validating this GET response.**
