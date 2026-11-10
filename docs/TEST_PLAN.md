# Phase 1 test plan

## Test A — iOS BLE discovery

1. Install the research build on the iPhone.
2. Wear/connect the WF-1000XM4 normally using iOS Bluetooth settings.
3. Open XM4Control and tap `Scan BLE`.
4. Record whether any peripheral appears with a Sony-like local name or service data.
5. Save the app's diagnostic output (do not publish personal identifiers).

Important: failure to discover a device does not prove the earbuds have no Bluetooth control channel. It only means this BLE scan did not discover an advertised BLE peripheral.

## Test B — no control writes

The Phase 1 app deliberately performs no GATT writes. Do not add guessed UUIDs or command bytes.

## Pass criteria

- A BLE peripheral is discovered consistently.
- A documented service/characteristic can be identified.
- Its purpose and write semantics are independently supported by evidence.
- A real-earbud test confirms a mode change.

Until all criteria pass, do not claim ANC control works.

## Phase 2 gate

If the only usable control transport is vendor RFCOMM/SPP and no public iOS API is available, stop direct iPhone control under the user's constraints (no extra hardware, no jailbreak).
