# BLE connection acceptance — 2026-11-22

App 0.2.13 (Android versionCode 2015), firmware 0.2.10, protocol 1.2.

The merged App includes manual scan lifecycle management, explicit native GATT discovery, connection-scoped characteristic resolution, Service Changed recovery that keeps output paused, UUID-only discovery diagnostics, and read failures identifying the failed UUID without native private error text. The pinned reactive_ble_mobile/RxAndroidBle patch and licenses live in `flutter_app/vendor/reactive_ble_mobile`; native regression instructions are in its PATCH.md.

Linux hardware acceptance used the shared DeviceSession with BlueZ: three connections, twelve paused seconds each, eighteen keepalive writes with advancing ACKs, 114 notifications, successful state/optional-feature reads, RELEASE and disconnect on every round. A transport whitelist prohibited ARM, target and configuration writes. Earlier intermittent supervision timeout (NimBLE 0x208 / HCI 0x08) was observed; its physical cause was not established. No firmware was flashed.

The Android phone still rejected the public identity characteristic 0001 with GATT_READ_NOT_PERMIT. This strongly indicated stale pre-migration GATT state; the phone ATT handle was not captured, so the precise stale mapping was not proven. Public discovery alone did not resolve it. After explicit user authorization and two matching private full-flash backups, the existing USB ble-recover-binding command cleared all BLE bonds and reset the pairing code. Normal firmware startup was confirmed. After phone-side Forget and re-pair, the user confirmed connection recovery and subsequently reported acceptance with no issues. Detailed phone acceptance steps were not recorded.

Recovery is an explicit maintenance action, never an automatic App retry: it removes all phone/host BLE bindings and resets the pairing code. The firmware rejects automatic replacement of an existing bond, so phone-only Forget is not a guaranteed recovery. Device application identity, mechanical calibration/board config and saved Wi-Fi are retained by the recovery code paths. Backups, keys, device captures and screenshots are not release artifacts and are excluded from this commit.

Repeat paused Linux acceptance with `dart run tool/ble_acceptance_probe.dart <known-address>`. Linux results cover BlueZ and the shared session, not the Android radio/cache implementation.

Merge validation: 193 Flutter tests passed; 7 Python delivery tests passed; Flutter analysis passed; Dart format reported 60 unchanged files; BLE contract check passed; ARM64 release build and APK signature verification passed. The resulting APK reports versionName 0.2.13 and versionCode 2015. A stale pre-vendoring plugin build cache had to be removed before the native rebuild. Native JVM regression tests were retained but not rerun during this merge.
