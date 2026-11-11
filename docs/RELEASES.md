# XM4Control releases

## v1.0.0 — stable baseline (2026-11-11)

**Frozen source branch:** [release/v1.0.0](https://github.com/t15575975/XM4/tree/release/v1.0.0)
**Baseline commit:** `b10de6431d51d7c4a679eb6477376aa8c91028b9`

The owner confirmed physical functionality working on a stock iPhone, including Sony ExternalAccessory V2 ANC control, one-shot mode cycling, and the iOS Shortcut / Action Button. The reported trace independently verified ANC → AMBIENT through Sony GET, SET ACK, and subsequent GET readback. Windows-side hardware tests had previously covered all three transitions.

Both the app and original status widget use `CFBundleShortVersionString=1.0.0` and build `100` in this frozen branch. This is a **pinned release branch**, not a Git tag or GitHub Release asset.

## v1.1.0 — interactive widget development

In `main`, the widget exposes **three explicit App Intent actions**: ANC, AMBIENT and OFF. The handler reads the real current Sony mode, performs at most one SET, and queries again for verification. It does not infer the selected mode from stale timeline data and does not optimistically claim a change. The app and widget are versioned `1.1.0` build `110`.

**Status:** code implementation / CI build; **direct WidgetKit interaction needs physical validation**. Widget intents normally run inside the widget extension process, unlike the separately validated main-app/Shortcut process. A CI success only proves that the code compiles; Sony EASession access from that extension and successful control from a locked screen are not yet proven.

## Install and test

1. Use the newest successful GitHub Actions `iOS build (unsigned research IPA)` artifact. It needs proper local signing before installation. Re-sign both `.app` and embedded `.appex` as required by the signing method.
2. Add **XM4 三模式控制** as a Home Screen widget (small or medium).
3. While stationary and with the phone unlocked, tap **降噪**, check the headphones; then separately tap **環境音** and **關閉**, each time checking the actual mode.
4. If a button fails to respond, try tapping the matching command from the App to distinguish the widget-extension environment from Sony transport. Do **not** repeatedly tap on unknown state.
5. The widget's audio-output text is an iPhone route snapshot, **not** the current Sony ANC mode. No Shared App Group entitlement or live ANC state feed is assumed.

The stable v1.0.0 branch remains available for rollback independently of this experiment.
