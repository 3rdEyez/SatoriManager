# Satori Android service discovery patch (2026-10-07)

Production plugin is vendored from reactive_ble_mobile 5.6.0. Its Dart and Darwin
implementation is unchanged. Upstream examples and tests are omitted; new native
regressions live under android/src/test/java. The app analyzer excludes unchanged
third-party Dart sources; it still analyzes every app source and app test.

RxAndroidBle stays at 1.16.0 rather than changing the whole connection stack.
Pinned official Maven artifacts are retained under android/upstream:

- AAR SHA-256: 903138c0d0d078d1c4aa00d7f62bd88acda54644a59cb8f6791c6d2129c73ea4
- Sources SHA-256: 240879d47d8ddc0f7aead592917c5f8f66220ccf9384c915acc892252758774d
- Source: https://repo.maven.apache.org/maven2/com/polidea/rxandroidble2/rxandroidble/1.16.0/
- License: Apache 2.0, matching the official Maven POM. Plugin LICENSE retained.

The Gradle satoriRxClasses task checks the original AAR checksum and keeps its
bytecode except four class families. Those four are rebuilt transparently from
the pinned official source, with these narrow changes:

1. ServiceDiscoveryManager never treats an existing getServices table as a
   successful new discovery. Explicit fresh discovery invalidates the completed
   connection cache and shares one pending operation; all UUID resolution then
   uses the newly completed table. Old generations cannot reset a replacement.
2. RxBleConnectionImpl exposes discoverServicesFresh; ordinary resolution keeps
   using the same connection-scoped manager, including read/write/notifications.
3. ServiceDiscoveryOperation calls public BluetoothGatt.discoverServices and
   waits for its actual completion callback. Timeout cannot fall back to a stale
   table; it terminates this connection because Android callbacks lack operation
   IDs. No public-discovery retry can consume a late callback on the same GATT.
4. RxBleGattCallback handles API 31 onServiceChanged by terminating the connection
   and its old subscriptions. DeviceConnector preserves a fixed safe marker to
   let the control engine reconnect while retaining paused output across retries.

SatoriGattDiscoveryEvidence is a new UUID/value-free, connection-scoped evidence
recorder: operation, API call acceptance, callback received/status and start/end
timestamps. The app reads this through the existing plugin method channel. It
does not export addresses, characteristic values, native exception text or keys.

There are no calls to hidden refresh(), unpair, cache deletion or security-setting
changes. The plugin's pre-existing clearGattCache implementation remains unused.
Public discovery may still return an Android system cache; this patch cannot
guarantee that a particular phone's OS returns the changed peripheral database.

Native test entry point: tools/test_android_discovery.py, from the repo root.
It runs the actual Gradle-compiled production classes. The OS/radio, timer and
physical read/write transport are controlled test doubles. A JVM-only no-op
BluetoothGattCallback replaces the SDK's throwing test stub; it is never packaged.
The end-to-end case starts with characteristics 1–5, sends a real production
discovery failure callback, then publicly discovers 1–9 and verifies the actual
plugin read/write/notification paths use new handles. Additional cases cover
timeouts, rejected starts, stale generations, duplicate discoveries, Service
Changed, and the native connection marker. Flutter regressions cover paused
recovery after a failed retry, no replay, failed-discovery I/O gating, and evidence
that arrives after disconnect.

JUnit console 1.11.4, Mockito 5.14.2, Byte Buddy/agent 1.15.4 and Objenesis 3.3
must be supplied in --test-libs. Runner arguments also select the existing JDK,
Android SDK android.jar, Gradle dependency cache and temporary output directory.
It does not access Bluetooth hardware, credentials, an emulator or the network.
