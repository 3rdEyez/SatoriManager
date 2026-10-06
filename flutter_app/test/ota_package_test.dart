import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ota_package.dart';

Map<String, Object?> manifest({int length = 4}) => {
  'schema': 1,
  'board': 'satori_c3_v1',
  'chip': 'esp32c3',
  'image_length': length,
  'sha256': 'ab' * 32,
  'version': '0.2.4',
  'image_format': 'esp-idf-sbv2-rsa3072',
};
List<int> container(Map<String, Object?> json, List<int> image) {
  final encoded = utf8.encode(jsonEncode(json));
  final length = encoded.length;
  return [
    length & 255,
    (length >> 8) & 255,
    (length >> 16) & 255,
    (length >> 24) & 255,
    ...encoded,
    ...image,
  ];
}

void main() {
  test('declared whole-bin SHA256 decodes 32 immutable bytes', () {
    final parsed = OtaPackageManifest.fromJson(manifest());
    expect(parsed.declaredSha256, List.filled(32, 0xab));
    expect(() => parsed.declaredSha256[0] = 0, throwsUnsupportedError);
  });
  test(
    'RSA format declaration is never signature verification or permission',
    () {
      for (final policy in [false, true]) {
        final checked = OtaPackagePreflight.inspect(
          manifest(),
          actualImageLength: 4,
          approvedTrustPolicy: policy,
        );
        expect(checked.signatureVerified, isFalse);
        expect(checked.authenticityEstablished, isFalse);
        expect(checked.mayTransfer, isFalse);
        expect(
          checked.block,
          policy
              ? OtaPackageBlock.signatureVerificationUnavailable
              : OtaPackageBlock.noApprovedTrustPolicy,
        );
      }
    },
  );
  test(
    'wrong target, schema, format, unknown and obsolete signature fields fail',
    () {
      for (final change in <Map<String, Object?>>[
        {'board': 'satori_s3'},
        {'chip': 'esp32s3'},
        {'schema': 2},
        {'schema': 1.0},
        {'unknown': true},
        {'image_format': 'unsigned'},
        {'image_format': 'ecdsa-p256-sha256'},
        {'signature': {}},
        {'board': 'satori_c3_v1\nchip=esp32s3'},
      ]) {
        expect(
          () => OtaPackageManifest.fromJson({...manifest(), ...change}),
          throwsFormatException,
        );
      }
      expect(
        () => OtaPackageManifest.fromJson({'schema': 1}),
        throwsFormatException,
      );
      expect(() => OtaPackageManifest.fromJson(null), throwsFormatException);
    },
  );
  test(
    'slot limit includes full signed image; invalid length/mismatch fail',
    () {
      for (final length in [1, OtaPackageManifest.slotBytes]) {
        expect(
          OtaPackagePreflight.inspect(
            manifest(length: length),
            actualImageLength: length,
          ).mayTransfer,
          isFalse,
        );
      }
      for (final length in [0, -1, 0x170001, 1.0, '4']) {
        expect(
          () => OtaPackageManifest.fromJson({
            ...manifest(),
            'image_length': length,
          }),
          throwsFormatException,
        );
      }
      for (final actual in [0, -1, 3, 5]) {
        expect(
          () => OtaPackagePreflight.inspect(
            manifest(),
            actualImageLength: actual,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'version boundaries, canonical decimal syntax and injection checked',
    () {
      for (final version in ['0.0.0', '65535.65535.65535']) {
        expect(
          OtaPackageManifest.fromJson({
            ...manifest(),
            'version': version,
          }).version,
          version,
        );
      }
      for (final version in [
        '65536.0.0',
        '0.65536.0',
        '0.0.65536',
        '01.2.3',
        '1.2',
        '1.2.3.4',
        '-1.2.3',
        '1.2.3-beta',
        '1.2.3\nkey_id=evil',
        '1.2.3\r',
        ' 1.2.3',
        '1.2.3 ',
        '１.2.3',
      ]) {
        expect(
          () =>
              OtaPackageManifest.fromJson({...manifest(), 'version': version}),
          throwsFormatException,
        );
      }
    },
  );
  test('SHA declaration must be exactly 32 lowercase hex bytes', () {
    for (final hash in [
      '',
      'ab' * 31,
      'ab' * 33,
      'AB' * 32,
      'gg' * 32,
      '${'ab' * 32}\n',
      List.filled(32, 0xab),
    ]) {
      expect(
        () => OtaPackageManifest.fromJson({...manifest(), 'sha256': hash}),
        throwsFormatException,
      );
    }
  });
  test(
    'length-prefixed container decodes raw image with immutable ownership',
    () {
      final raw = container(manifest(), [0xe9, 0, 0, 0]);
      final parsed = OtaPackageContainer.decode(raw);
      expect(parsed.manifest.version, '0.2.4');
      expect(parsed.imageBytes, [0xe9, 0, 0, 0]);
      raw[raw.length - 1] = 1;
      expect(parsed.imageBytes.last, 0);
      expect(() => parsed.imageBytes[0] = 0, throwsUnsupportedError);
      // Tiny unsigned bytes are only structural input, never authenticated.
      expect(
        OtaPackagePreflight.inspect(
          manifest(),
          actualImageLength: 4,
        ).mayTransfer,
        isFalse,
      );
    },
  );
  test(
    'truncated/oversized prefix, payload trailing bytes and invalid JSON fail',
    () {
      final good = container(manifest(), [1, 2, 3, 4]);
      for (final raw in <List<int>>[
        [],
        [1, 0, 0],
        [0, 0, 0, 0, 1],
        [1, 4, 0, 0, 1],
        [255, 255, 255, 255, 1],
        [5, 0, 0, 0, 1],
        [1, 0, 0, 0, 0xff, 1],
        [1, 0, 0, 0, 0x7b, 1],
        [2, 0, 0, 0, 0x5b, 0x5d, 1],
        good.sublist(0, good.length - 1),
        [...good, 0],
        [...good.sublist(0, good.length - 1), 256],
        List.filled(4 + 1024 + OtaPackageManifest.slotBytes + 1, 0),
      ]) {
        expect(() => OtaPackageContainer.decode(raw), throwsFormatException);
      }
    },
  );
}
