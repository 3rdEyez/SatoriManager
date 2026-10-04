#!/usr/bin/env python3
"""Plan a public development bundle; explicit --execute writes a new archive."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

APP = Path(__file__).resolve().parents[1]
PROFILES = ('ble_primary', 'legacy_udp', 'ble_dual_ota', 'ble_wifi_ota_prototype')

def digest(data):
    return hashlib.sha256(data).hexdigest()

class Parser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, 'Invalid arguments; see --help. Never put secrets in argv.\n')

def public_files(firmware, apk, profiles):
    files = {'android/app-arm64-v8a-release.apk': apk,
             'docs/BLE_IMPLEMENTATION.md': APP / 'docs/BLE_IMPLEMENTATION.md',
             'docs/BLE_LINUX.md': APP / 'BLE_LINUX.md'}
    for name in ('FIRMWARE_SETUP.md', 'SatoriEye_BLE_Protocol_v1.md',
                 'satori_ble_v1_2_shared_pairing_vectors.json',
                 'satori_ble_v1_1_management_vectors.json', 'satori_ble_v1_golden_vectors.json'):
        files['protocol/' + name] = firmware / 'docs/ble/v1' / name
    for profile in profiles:
        for name in ('app.bin', 'bootloader/bootloader.bin', 'partition_table/partition-table.bin', 'flasher_args.json'):
            files['firmware/' + profile + '/' + name] = firmware / 'build' / profile / name
    return files

def apk_version(apk, aapt):
    result = subprocess.run([aapt, 'dump', 'badging', str(apk)], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise ValueError('APK metadata verification failed')
    name = re.search(r"versionName='([^']+)'", result.stdout)
    code = re.search(r"versionCode='([0-9]+)'", result.stdout)
    if not name or not code:
        raise ValueError('APK metadata unavailable')
    return name[1] + '+' + code[1]

def snapshots(files):
    result = {}
    for name, path in files.items():
        absolute = path.absolute()
        if any(parent.is_symlink() for parent in (absolute, *absolute.parents)):
            raise ValueError('Public inputs must not be symbolic links')
        result[name] = path.read_bytes()
    return result

def create(files, output, version, profiles):
    # Exclusive creation; no directory traversal, generated sdkconfig, NVS or logs.
    content = snapshots(files) if any(isinstance(item, Path) for item in files.values()) else files
    manifest = {'app_version': version, 'profiles': profiles,
                'android_signing': 'not verified by this tool', 'hardware_verified': False,
                'firmware_signature': 'not verified by this bundle tool; use satori_dev package',
                'files': {name: {'bytes': len(data), 'sha256': digest(data)}
                          for name, data in content.items()}}
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in content.items():
            archive.writestr(name, data)
        archive.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        archive.writestr('README.txt', 'Development artifacts; hardware acceptance pending.\n'
                          'Profiles are mutually exclusive. Do not erase NVS or calibration.\n'
                          'This archive is not an automatic flash or OTA package.\n')
    return {'bundle_written': True, 'sha256': digest(output.read_bytes())}

def main(argv=None):
    parser = Parser(description=__doc__)
    parser.add_argument('--firmware-root', type=Path, required=True)
    parser.add_argument('--apk', type=Path, default=APP / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--profile', action='append', choices=PROFILES)
    parser.add_argument('--aapt', default=shutil.which('aapt'))
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args(argv)
    try:
        profiles = list(dict.fromkeys(args.profile or ['ble_primary', 'legacy_udp']))
        files = public_files(args.firmware_root.absolute(), args.apk, profiles)
        if not args.execute:
            print(json.dumps({'offline_plan': True, 'bundle_written': False,
                              'missing_public_entries': [name for name, path in files.items() if not path.is_file()]}))
            return 0
        if any(not path.is_file() for path in files.values()) or not args.aapt:
            raise ValueError('Public inputs or aapt unavailable')
        expected = next(line.split(':', 1)[1].strip() for line in (APP / 'pubspec.yaml').read_text().splitlines() if line.startswith('version:'))
        content = snapshots(files)
        with tempfile.TemporaryDirectory(prefix='satori-public-apk-') as directory:
            frozen = Path(directory) / 'app.apk'
            frozen.write_bytes(content['android/app-arm64-v8a-release.apk'])
            actual = apk_version(frozen, args.aapt)
        if actual != expected:
            raise ValueError('APK does not match current source version')
        print(json.dumps(create(content, args.output, actual, profiles)))
        return 0
    except Exception as error:
        print(json.dumps({'operation_failed': True, 'error_type': type(error).__name__, 'details_withheld': True}))
        return 2

if __name__ == '__main__':
    raise SystemExit(main())
