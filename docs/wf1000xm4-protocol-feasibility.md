# WF-1000XM4 protocol feasibility (2026-11-11)

## Verified on the user's iPhone
- CoreBluetooth discovers `LE_WF-1000XM4` and connects.
- 7 GATT services: `5B833E06`, `5B833E0A`, `5B833E26` (all suffix `-6BC7-4802-8E9A-723CECA4BD8F`), `DC405470-A351-4A59-97D8-2E2E3B207FBB`, `180A`, `FE03`, `FE2C`.
- Device information reads model WF-1000XM4, firmware 2.3.1.
- Read and notify operations work on several characteristics. There is **no evidence yet** that any GATT characteristic controls ANC.
- Separate connection logs for Off, ANC and Ambient show the same GATT inventory, with no mode-specific value proven.

## Verified open-source reference
- [Obito1903/sony-headphones-ctl](https://github.com/Obito1903/sony-headphones-ctl), archived MIT Rust CLI for WF-1000XM4.
- Its [protocol documentation](https://github.com/Obito1903/sony-headphones-ctl/blob/main/docs/README.md) states **RFCOMM** transport, `DataMdr` packet type `0x0C`, ANC write code `0x6815`, ANC read code `0x6915`.
- ANC payload documented as six bytes: continuous mode, NC enable, NC mode, wind setting, voice passthrough, level (0–20). Wind values documented: 0x02 disabled, 0x03 enabled without voice passthrough, 0x05 enabled with voice passthrough.
- These bytes are **Sony RFCOMM protocol payloads, not proven BLE GATT commands**. Never transmit them into arbitrary writable GATT characteristics.
- [marconvcm/sony-device-center](https://github.com/marconvcm/sony-device-center) is a desktop C++ implementation explicitly using Bluetooth RFCOMM; its compatibility lists are not hardware validation for this iOS transport.
- [ibatra/sony-headphones-client](https://github.com/ibatra/sony-headphones-client) also describes RFCOMM.

## Decision / gate
**Do not implement an ANC write operation or Shortcut App Intent yet.** First establish one of:
1. An observed BLE request/response protocol with verified ANC semantics on WF-1000XM4, or
2. A documented, iOS-accessible alternative transport capable of sending the known Sony command, without jailbreaking or extra hardware.

CoreBluetooth GATT access does not expose generic Bluetooth Classic RFCOMM sockets. An iOS BLE characteristic that happens to be writable is insufficient evidence.

## Next experiment
- Keep the read-only GATT monitor connected while changing modes, and log actual notifications with service UUID, characteristic UUID and bytes.
- Distinguish connection setup and subscription errors from actual mode-dependent notifications.
- If app backgrounding suspends observations, collect a simultaneous trace via an allowed tool/OS mechanism; do not infer that a silent log means no traffic.
- Compare repeated A/B/A/B mode transitions before assigning semantics.
- Preserve exact device firmware, transport and provenance in each test.

## Status
Research only. No verified ANC/ambient/off control via iOS. No production-ready Action Button cycle.
