# Phase 1 — protocol and iOS feasibility audit

Date: 2026-11-11

## Device target

Sony WF-1000XM4 true wireless earbuds (not WH-1000XM4).

## Public reverse-engineering evidence

- `AmitRajput-Dev/SonyBridge` describes Sony's vendor RFCOMM/SPP control channel and a second-generation protocol. Its README lists WF-1000XM4 as an expected v2 earbud target, but explicitly says only WH-CH720N is fully hardware-verified and that per-model quirks remain untested.
- `Obito1903/sony-headphones-ctl` is an archived Linux CLI targeting WF-1000XM4 and documents ANC / ambient configuration. It is not an iOS implementation.
- `ibatra/sony-headphones-client` describes a desktop RFCOMM implementation; its platform table says Windows tested, Linux untested, and macOS stub.

## iOS feasibility

- Apple's Core Bluetooth is the supported public framework for BLE communication. Its documentation mentions LE and BR/EDR technology, but does not expose a general-purpose RFCOMM/SPP socket API for arbitrary third-party apps.
- Apple's External Accessory framework is for supported MFi accessories and is not a generic escape hatch for Sony's private SPP service.
- Thus, copying a desktop RFCOMM implementation into an iOS app is not a valid plan without identifying a supported iOS API and a compatible service transport.

## Phase 1 conclusion

**Direct RFCOMM/SPP control from an ordinary App Store-style iOS app is currently unproven and likely blocked by public API availability.**

This project starts with a BLE discovery test only. If the earbuds expose a usable BLE GATT control service (not established by the desktop RFCOMM projects), the next step can test that service. If no such service exists, stop the direct-control route rather than pretending that the desktop protocol can be sent from iOS.

## Sources

- https://github.com/AmitRajput-Dev/SonyBridge
- https://github.com/Obito1903/sony-headphones-ctl
- https://github.com/ibatra/sony-headphones-client
- https://developer.apple.com/documentation/corebluetooth
- https://developer.apple.com/documentation/externalaccessory
