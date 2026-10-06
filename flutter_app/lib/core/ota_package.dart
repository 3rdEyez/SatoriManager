import 'dart:convert';

/// Offline syntax/target preflight only. No files, network, keys or verification.
class OtaPackageManifest {
  OtaPackageManifest._({
    required this.imageLength,
    required this.sha256Hex,
    required this.version,
  });
  static const board = 'satori_c3_v1';
  static const chip = 'esp32c3';
  static const slotBytes = 0x170000;
  static const imageFormat = 'esp-idf-sbv2-rsa3072';
  final int imageLength;
  final String sha256Hex, version;

  factory OtaPackageManifest.fromJson(Object? value) {
    const fields = {
      'schema',
      'board',
      'chip',
      'image_length',
      'sha256',
      'version',
      'image_format',
    };
    if (value is! Map<String, Object?> ||
        value.length != fields.length ||
        !fields.every(value.containsKey)) {
      throw const FormatException('Invalid OTA manifest fields');
    }
    if (value['schema'] is! int ||
        value['schema'] != 1 ||
        value['board'] != board ||
        value['chip'] != chip ||
        value['image_format'] != imageFormat) {
      throw const FormatException(
        'Unsupported OTA schema, target or image format',
      );
    }
    final length = value['image_length'];
    if (length is! int || length <= 0 || length > slotBytes) {
      throw const FormatException(
        'OTA image does not fit the application slot',
      );
    }
    final hash = value['sha256'];
    if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid OTA SHA256 declaration');
    }
    final version = value['version'];
    if (version is! String || !_validVersion(version)) {
      throw const FormatException('Invalid OTA version');
    }
    return OtaPackageManifest._(
      imageLength: length,
      sha256Hex: hash,
      version: version,
    );
  }

  /// The declared whole .bin digest, including padding and its signature block.
  /// This does not hash or authenticate an image.
  List<int> get declaredSha256 => List<int>.unmodifiable([
    for (var i = 0; i < sha256Hex.length; i += 2)
      int.parse(sha256Hex.substring(i, i + 2), radix: 16),
  ]);

  static bool _validVersion(String value) {
    if (!RegExp(
      r'^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$',
    ).hasMatch(value)) {
      return false;
    }
    return value.split('.').every((part) => int.parse(part) <= 65535);
  }
}

/// Candidate .sota: uint32 LE manifest length, UTF-8 JSON, then the whole raw .bin.
/// No archive extraction, file access, digest computation or signature parsing.
class OtaPackageContainer {
  OtaPackageContainer._(this.manifest, this.imageBytes);
  static const maxManifestBytes = 1024;
  final OtaPackageManifest manifest;
  final List<int> imageBytes;

  factory OtaPackageContainer.decode(List<int> bytes) {
    if (bytes.length < 5 ||
        bytes.length > 4 + maxManifestBytes + OtaPackageManifest.slotBytes ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Invalid OTA container size or bytes');
    }
    final length =
        bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    if (length <= 0 ||
        length > maxManifestBytes ||
        4 + length >= bytes.length) {
      throw const FormatException('Invalid OTA manifest length prefix');
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes.sublist(4, 4 + length)));
    } on FormatException {
      // Do not echo untrusted JSON or file contents in diagnostic messages.
      throw const FormatException('Invalid OTA manifest JSON');
    }
    final manifest = OtaPackageManifest.fromJson(json);
    if (bytes.length - 4 - length != manifest.imageLength) {
      throw const FormatException('OTA image length differs from manifest');
    }
    return OtaPackageContainer._(
      manifest,
      List<int>.unmodifiable(bytes.sublist(4 + length)),
    );
  }
}

enum OtaPackageBlock { noApprovedTrustPolicy, signatureVerificationUnavailable }

class OtaPackagePreflight {
  OtaPackagePreflight._(this.manifest, this.block);
  final OtaPackageManifest manifest;
  final OtaPackageBlock block;

  factory OtaPackagePreflight.inspect(
    Object? manifestJson, {
    required int actualImageLength,
    bool approvedTrustPolicy = false,
  }) {
    final manifest = OtaPackageManifest.fromJson(manifestJson);
    if (actualImageLength != manifest.imageLength) {
      throw const FormatException('OTA image length differs from manifest');
    }
    return OtaPackagePreflight._(
      manifest,
      approvedTrustPolicy
          ? OtaPackageBlock.signatureVerificationUnavailable
          : OtaPackageBlock.noApprovedTrustPolicy,
    );
  }

  // A format declaration or caller policy flag never supplies crypto proof.
  bool get signatureVerified => false;
  bool get authenticityEstablished => false;
  bool get mayTransfer => false;
}
