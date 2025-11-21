import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/network.dart';

class CekSecretClient {
  const CekSecretClient._();

  static const String _cekSecretPath = '/sdk/cek-secret';

  /// Fetches the CEK secret blob for a model by signing the
  /// `GET /sdk/cek-secret` request with the SDK key pair.
  static Future<Map<String, dynamic>?> fetchCekSecret({
    required String apiKeyId,
    required String apiKeySecret,
    required String modelKey,
    String? aad,
    String? overrideBaseUrl,
    http.Client? client,
  }) async {
    final resolvedBase = _resolveBaseUrl(overrideBaseUrl);
    if (resolvedBase == null) {
      debugPrint(
        'fetchCekSecret missing base URL. Provide overrideBaseUrl or define EMOTION_SERVER_URL.',
      );
      return null;
    }

    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    const path = _cekSecretPath;
    final canonical = '$timestamp\nGET\n$path';
    final hmac = Hmac(sha256, utf8.encode(apiKeySecret));
    final signature = base64Encode(hmac.convert(utf8.encode(canonical)).bytes);

    final queryParams = <String, String>{'modelKey': modelKey};
    if (aad != null && aad.isNotEmpty) {
      queryParams['aad'] = aad;
    }

    final uri =
        Uri.parse('$resolvedBase$path').replace(queryParameters: queryParams);
    final headers = <String, String>{
      'X-SDK-Key-Id': apiKeyId,
      'X-SDK-Timestamp': timestamp,
      'X-SDK-Signature': signature,
    };

    final httpClient = client ?? http.Client();
    try {
      final resp = await httpClient.get(uri, headers: headers);
      if (resp.statusCode != 200) {
        debugPrint('fetchCekSecret failed: ${resp.statusCode} ${resp.body}');
        return null;
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }

      debugPrint('fetchCekSecret malformed response: $decoded');
    } catch (error) {
      debugPrint('fetchCekSecret exception: $error');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
    return null;
  }

  static String? _resolveBaseUrl(String? overrideBaseUrl) {
    final trimmed = (overrideBaseUrl?.trim().isNotEmpty ?? false)
        ? overrideBaseUrl!.trim()
        : emotionServerUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
