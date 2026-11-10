# XM4Control

Experimental iOS companion project for Sony WF-1000XM4.

## Phase 1 status

This repository is a **research/test scaffold**, not a working noise-control app.

The public Sony reverse-engineering projects describe a vendor Bluetooth Classic RFCOMM/SPP control channel. Their desktop implementations do not prove that a third-party iOS app can open that channel. Apple's Core Bluetooth is not a general RFCOMM socket API, and External Accessory is intended for supported MFi accessories.

Therefore this first build only tests what iOS can discover through CoreBluetooth (BLE). It does **not** send Sony control packets and does not change ANC modes.

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
