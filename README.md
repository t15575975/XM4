# XM4Control

Experimental iOS companion project for Sony WF-1000XM4.

## Current status (2026-11-11)

**Windows Sony ANC control confirmed on physical WF-1000XM4 firmware 2.3.1.** The native Winsock2 tool connected via Bluetooth Classic RFCOMM channel 9, read the Sony V2 `67 15` status, sent `68 15 01 00 00 02 00 14`, received an ACK, and read back **OFF**. The wearer separately confirmed that ANC/environmental processing truly switched off. The previously active mode was AMBIENT level 20.

- `--native-read-anc`: read the real current ANC mode, no setting change (verified).
- `--set-off`: set OFF with read-before-write / readback verification (verified from AMBIENT).
- `--set-anc`, `--set-ambient`, `--cycle`: implemented and CI-compiled, **not yet hardware-verified** for all transitions.
- [Windows validation log and source evidence](docs/windows-rfcomm-validation.md).

From a Windows checkout in `tools/XM4SdpProbe`, use `dotnet run -- --cycle` for one step in the requested **ANC → AMBIENT → OFF → ANC** sequence; every command reads the current mode before setting and verifies the result. Test only while stationary.

**iPhone direct-control goal is still blocked.** The iOS project can scan/read BLE, but no usable iOS Sony ANC transport has been validated. Public iOS CoreBluetooth is not a general RFCOMM socket API; ExternalAccessory access needs accessory protocol support. Windows success must not be described as a working iPhone Action Button/IPA solution.

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
