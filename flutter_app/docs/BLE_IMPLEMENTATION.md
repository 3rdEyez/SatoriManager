# BLE A0/A1 implementation and acceptance

This is the Flutter replacement path for Qt. It is a development release, not a
claim of verified wearable or Android lock-screen operation.

## Ownership and flow

The Android `connectedDevice` foreground service creates one FlutterEngine-owned
`ReactiveBleLink`, `DeviceSession`, and `ControlEngine`. The visible UI requests
permissions, starts that service, and exchanges semantic commands and versioned
snapshots. UI recreation does not transfer a connection or restart actions.

The flow is scan → connect → protected access/system pairing → authenticated
identity check → EventTX subscription → CLAIM → load built-in or saved limits → automatic ARM.
Every reconnect also requests ARM, without replaying prior actions. A pause cancels
the pending start throughout the current recovery round, including backoff and
failed attempts. Built-in product defaults remove mandatory setup. Explicit malformed board
configuration still keeps output paused with an explanation. The App reads the
resulting three-channel state before merging any partial movement. The built-in startup [1500,1500,1500] derives from the production Qt client;
it is not presented as measured mechanical validation.

The service holds a CPU wake lock for its user-started lifetime so its heartbeat
and action timers can run with the screen off. It holds no Wi-Fi lock and does
not restart on boot or package replacement. Ending the service releases the lock.
Battery impact, Doze and OEM lifecycle behavior still require real Android tests.

Android's notification subscription API in the chosen BLE plugin has no explicit
CCCD-ready callback. Pairing is completed through protected access before command
timers start. CLAIM setup must tolerate a bounded SUBSCRIPTION_REQUIRED response;
no other command rejection is treated as success or silently downgraded.

## Control semantics

- Wire values 500–2500 are **logical input encoding**, not final servo pulse widths.
- UI target, firmware last-commanded values, and physical position are different.
  Physical position and unsampled battery are unknown.
- Commands have both GATT completion and protocol business ACK. Neither proves
  physical arrival. HALT confirmation means interpolation was cancelled.
- Manual input has one pending latest target, max 20 Hz, and one GATT writer.
- Presets preserve keyframes, wait for acceptance and keep their own `duration`;
  transition defaults to 200 ms. More than 100 ms late cancels the remaining preset.
- Manual takeover cancels prior actions. Pause clears pending targets/timers and
  asks firmware to hold its last legal output; it does not center or open the lid.
- Disconnect clears all scheduling. Retry delays are 1/2/4/8 seconds, then manual
  retry. Reconnected sessions request ARM automatically and never replay prior frames.

## Devices and limits

Pairing secrets and OS bond keys are not stored in Flutter preferences. Preferences
contain only authenticated identity, last radio address/name and user-confirmed
logical limits. A radio address/name is not an authentication credential. Lost
system bonding requires the documented USB maintenance flow; reinstalling this
App is not a device reset.

Set all three safe ranges in the device page. Firmware owns startup posture and
mechanical calibration. Invalid or absent firmware configuration makes ARM fail
with NOT_CONFIGURED, while scanning, pairing and status diagnostics remain usable.

## Qt replacement matrix

| Original capability | This BLE slice | Remaining work |
|---|---|---|
| Discovery / connection | BLE device page, authenticated identity, automatic ARM after safety checks | Real phone/device qualification |
| Manual CH1/CH2/CH3 | Joystick, lid control, local confirmed limits | Physical small-travel validation |
| Auto/Manual | Dart engine and manual takeover | Final parameter UX |
| Automatic eye movement | Bounded center-region random movement, fixed 5 s interval | Legacy normal distribution/range/interval options |
| Automatic blinking | Existing wink/wink2, fixed 5 s interval | Legacy random blink interval/jitter |
| Bundled wink/wink2 | Preserved JSON proportions/-1 and frame timing | Physical observation |
| External preset JSON loading | Parser retained, bundled presets usable | User file import UI |
| Cancel / disconnect | Firmware HALT/RELEASE confirmation plus local cancellation | Notification and radio-loss hardware matrix |
| Battery | Unknown without actual sampling | Hardware sampling if available |
| UDP / existing firmware | Codec, simulator and legacy engine retained for regression | Optional Flutter product UDP entry in later phase |
| Sleep | Not exposed; no verified firmware contract | Separate capability/protocol design if needed |
| Joystick release recenter toggle | Retained on the Flutter control page; uses confirmed safe ranges | Preference persistence remains later work |
| FacialRecognition mode button | No BLE operation; Qt has a mode request, no vision pipeline in this repo | Camera/vision feature and firmware contract are out of scope |
| Pupil-size dial | Qt display-only dial has no channel handler; not presented as a working BLE capability | Hardware/protocol support required |
| Settings “save” button | Qt handler only logged a message; BLE stores authenticated identity and confirmed safety limits | Persist remaining local Auto/joystick preferences later |
| Heartbeat / lost-connection recovery | BLE lease plus bounded reconnect and automatic ARM, no action replay | Radio-loss hardware acceptance |
| Background operation | Single service-owned runtime and notification actions | Android lock-screen/Doze acceptance |

The matrix was checked against `SatoriManagerContent/mobileclient.h`,
`mobileclient.cpp`, `ScreenMain.qml`, `ScreenControlForm.ui.qml`, `Setting.qml`,
`SettingForm.ui.qml`, `ControlStick.qml`, and `ActionPresetLoader.cpp`. It includes
placeholder controls separately from implemented Qt behavior.

Qt source is retained for history. Qt is not required to operate the BLE client.
The BLE firmware is not compatible with Qt/UDP at runtime. Recovery uses the
separate legacy firmware build or a previously backed-up image.

## Reproducible checks

Run `dart run tool/check_ble_contract.dart`, `flutter analyze`, and `flutter test` from `flutter_app/` with the pinned Flutter SDK. Build Android with `flutter build apk --debug` or `flutter build apk --release --split-per-abi`.

## Pairing and controls

Firmware protocol 1.2 supports up to eight stored phone bonds and one live connection. An authenticated phone may change the shared pairing code; existing bonds remain valid. New devices initialize with code 123456. Connections authorize output after authenticated CLAIM and ARM; a user pause revokes automatic startup for the current reconnect round.

Manual joystick and eyelid input use a 50 ms transition and a latest-target slot capped by the device's 20 Hz limit. Preset and automatic actions keep 200 ms transitions. The notification and UI read structured control state to distinguish pausing, paused, unconfirmed pause, and configuration errors. Raw exceptions and logical channel targets are shown only in the collapsed diagnostics section.

Release APKs currently use a development signing key. Physical position is not measured; a business ACK confirms command acceptance, not mechanical arrival. Device-specific and Android lifecycle checks must be performed before production use.
