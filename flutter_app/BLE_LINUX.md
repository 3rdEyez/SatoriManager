# Linux BLE diagnostic adapter

`tool/ble_probe.dart` uses the system BlueZ daemon and the shared
`DeviceSession` implementation. BlueZ pairing requests are delegated to its
registered system agent. The utility never accepts passkeys as arguments or
prints session tokens.

Run a bounded eight-second scan:

```sh
dart run tool/ble_probe.dart
```

Without a device argument, the tool scans only and exits. To connect to a
previously discovered address, pass `--device <address>`. That path reads the
identity and capabilities, subscribes to EventTX, claims a paused session,
reads the current state, then releases and disconnects.

Output remains disabled unless `--arm` is explicitly present. A target needs
both `--arm` and three comma-separated channel values, each in the protocol
range 500–2500. The tool HALTs after a target is acknowledged:

```text
dart run tool/ble_probe.dart --device <address> --arm --target=<CH1>,<CH2>,<CH3>
```

Use only a mechanically verified safe start and channel limits. The protocol
range is an input encoding and is not a mechanical safety range.

The CLI help and scan smoke checks need no Android phone after Flutter package
dependencies have been resolved:

```sh
dart run tool/ble_probe.dart --help
dart run tool/ble_probe.dart
```

Adapter source analysis:

```sh
flutter analyze lib/infrastructure/reactive_ble_link.dart \
  lib/infrastructure/bluez_ble_link.dart \
  lib/infrastructure/ble_discovery.dart tool/ble_probe.dart
```

In this workspace, adapter analysis passed. A host scan completed without
finding a SatoriEye service. No device was connected and no pairing or
Bluetooth setting was changed. This does not validate radio interoperability,
GATT security, or firmware behavior on hardware.

New firmware bootstraps a truly empty device with default passkey `123456`. Existing identities and codes are preserved. Enter the appropriate code in the BlueZ pairing agent. v1.2 retains up to eight phone bonds with one live connection. Code changes are available in the Android device page and retain existing bonds. Android starts configured output automatically after connecting; the Linux probe remains an explicit control diagnostic and does not inherit that App policy.
