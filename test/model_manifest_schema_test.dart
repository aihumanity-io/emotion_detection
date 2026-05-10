import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model package manifest schema', () {
    test('accepts the phase 0 fixture', () {
      final manifest =
          _loadManifest('test/resources/model_manifests/valid_fer2025.json');

      expect(_validateManifest(manifest), isEmpty);
    });

    test('rejects unsupported schema versions', () {
      final manifest = _loadManifest(
        'test/resources/model_manifests/invalid_unsupported_version.json',
      );

      expect(_validateManifest(manifest),
          contains('unsupported manifest_schema_version'));
    });

    test('rejects missing required fields', () {
      final manifest =
          _loadManifest('test/resources/model_manifests/valid_fer2025.json')
            ..remove('encrypted_sha256');

      expect(_validateManifest(manifest), contains('missing encrypted_sha256'));
    });
  });
}

Map<String, Object?> _loadManifest(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw StateError('Manifest fixture must be a JSON object: $path');
  }
  return decoded;
}

List<String> _validateManifest(Map<String, Object?> manifest) {
  final errors = <String>[];
  const requiredFields = <String>{
    'manifest_schema_version',
    'model_id',
    'model_version',
    'model_format',
    'input_shape',
    'labels',
    'aad',
    'kdf_info',
    'shard_required',
    'expiry_epoch_ms',
    'encrypted_sha256',
    'plaintext_sha256',
    'runtime_min_version',
    'sdk_min_version',
    'signature_algorithm',
  };

  for (final field in requiredFields) {
    if (!manifest.containsKey(field)) {
      errors.add('missing $field');
    }
  }

  if (manifest['manifest_schema_version'] != 1) {
    errors.add('unsupported manifest_schema_version');
  }
  if (manifest['model_format'] != 'onnx') {
    errors.add('unsupported model_format');
  }

  final labels = manifest['labels'];
  if (labels is! List ||
      labels.isEmpty ||
      labels.any((label) => label is! String)) {
    errors.add('invalid labels');
  }

  final inputShape = manifest['input_shape'];
  if (inputShape is! List ||
      inputShape.isEmpty ||
      inputShape.any((dimension) => dimension is! int || dimension <= 0)) {
    errors.add('invalid input_shape');
  }

  final kdfInfo = manifest['kdf_info'];
  if (kdfInfo is! Map || kdfInfo['algorithm'] != 'hkdf-sha256') {
    errors.add('invalid kdf_info');
  }

  for (final field in ['encrypted_sha256', 'plaintext_sha256']) {
    final value = manifest[field];
    if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      errors.add('invalid $field');
    }
  }

  return errors;
}
