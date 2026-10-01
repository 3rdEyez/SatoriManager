#!/usr/bin/env python3
"""Bundle only reviewed public artifacts; never include NVS/config/USB logs."""
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

APP = Path(__file__).resolve().parents[1]
REPO = APP.parent
FIRMWARE = REPO.parent / "ESP-3RDEYE"
OUTPUT = APP / "build" / "satori-ble-a0-a1.zip"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def head(repo):
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()


def source_fingerprint(root, directories, extra_files):
    paths = set()
    for directory in directories:
        paths.update(path for path in (root / directory).rglob("*")
                     if path.is_file() and path.suffix in (".dart", ".cpp", ".hpp", ".h", ".c", ".json", ".xml", ".kt", ".kts", ".yaml", ".txt"))
    paths.update(root / item for item in extra_files)
    entries = {str(path.relative_to(root)): digest(path.read_bytes()) for path in sorted(paths) if path.is_file()}
    return {"sha256": digest(json.dumps(entries, sort_keys=True).encode()), "inputs": entries}


def main():
    files = {
        "android/app-arm64-v8a-release.apk": APP / "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk",
        "docs/BLE_IMPLEMENTATION.md": APP / "docs/BLE_IMPLEMENTATION.md",
        "docs/BLE_LINUX.md": APP / "BLE_LINUX.md",
        "docs/FIRMWARE_SETUP.md": FIRMWARE / "docs/ble/v1/FIRMWARE_SETUP.md",
        "protocol/SatoriEye_BLE_Protocol_v1.md": FIRMWARE / "docs/ble/v1/SatoriEye_BLE_Protocol_v1.md",
        "protocol/satori_ble_v1_2_shared_pairing_vectors.json": FIRMWARE / "docs/ble/v1/satori_ble_v1_2_shared_pairing_vectors.json",
        "protocol/satori_ble_v1_1_management_vectors.json": FIRMWARE / "docs/ble/v1/satori_ble_v1_1_management_vectors.json",
        "protocol/satori_ble_v1_golden_vectors.json": FIRMWARE / "docs/ble/v1/satori_ble_v1_golden_vectors.json",
    }
    # Explicit whitelist: no merged flash, NVS, board configuration, sdkconfig,
    # credentials, pairing cards, USB captures or developer build logs.
    for profile in ("ble_primary", "legacy_udp"):
        for relative in ("app.bin", "bootloader/bootloader.bin", "partition_table/partition-table.bin", "flasher_args.json"):
            files[f"firmware/{profile}/{relative}"] = FIRMWARE / "build" / profile / relative
    missing = [str(path) for path in files.values() if not path.is_file()]
    if missing:
        raise SystemExit("Missing build artifacts: " + ", ".join(missing))
    manifest = {
        "release": "SatoriEye BLE A0/A1 software candidate",
        "app_version": next(line.split(":", 1)[1].strip() for line in (APP / "pubspec.yaml").read_text().splitlines() if line.startswith("version:")) + " release",
        "android_abi": "arm64-v8a",
        "android_signing": "development key (not a production signing identity)",
        "app_base_head": head(REPO),
        "firmware_base_head": head(FIRMWARE),
        "source_state": "Uncommitted working-tree implementation; HEAD alone does not identify this build",
        "hardware_verified": False,
        "source_fingerprints": {
            "app": source_fingerprint(APP, ("lib", "assets", "android/app/src"), ("pubspec.yaml", "pubspec.lock", "android/app/build.gradle.kts")),
            "firmware": source_fingerprint(FIRMWARE, ("main",), ("CMakeLists.txt", "main/Kconfig.projbuild", "dependencies.lock", "sdkconfig.defaults", "sdkconfig.ble_primary.defaults", "sdkconfig.legacy_udp.defaults", "partitions.csv", "build/ble_primary/sdkconfig", "build/legacy_udp/sdkconfig")),
        },
        "files": {},
    }
    with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=3) as archive:
        for name, path in files.items():
            content = path.read_bytes()
            archive.writestr(name, content)
            manifest["files"][name] = {"bytes": len(content), "sha256": digest(content)}
        archive.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        archive.writestr("README.txt", """SatoriEye BLE A0/A1 development build
Read docs/BLE_IMPLEMENTATION.md and docs/FIRMWARE_SETUP.md before use.
Android APK is an arm64-v8a release build with a development signing key.
Hardware pairing, movement and background tests are pending.
BLE and legacy_udp are mutually exclusive firmware profiles. Do not combine them.
Firmware directories contain app/bootloader/partition table plus flash offset metadata.
No NVS, credentials, identity, pairing card or board configuration is included.
Do not overwrite existing NVS or calibration during upgrade. Back up the device first.
Built-in product defaults enable output after an authenticated App connection.
Existing maintenance overrides and mechanical calibration remain in effect.
Built-in values are not a claim of completed hardware validation.
Code changes and runnable simulators are in the two source workspaces, not this artifact archive.
The documentation's source-relative links refer to those workspaces.
See manifest.json for every included artifact's size and SHA-256.
""")
    sidecar = OUTPUT.with_suffix(".manifest.json")
    sidecar.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Bundle: {OUTPUT}")
    print(f"Bytes: {OUTPUT.stat().st_size}")
    archive_hash = digest(OUTPUT.read_bytes())
    OUTPUT.with_suffix(".zip.sha256").write_text(archive_hash + "  " + OUTPUT.name + "\n")
    print(f"SHA-256: {archive_hash}")


if __name__ == "__main__":
    main()
