import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/network.dart';
import '../native/model_runtime.dart';

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
    bool cacheShardOnIOS = false,
    String methodChannelName = 'face_emotion_detection',
    String? modelIdForShard,
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
    final normalizedAad = aad?.trim().toLowerCase();
    if (normalizedAad != null && normalizedAad.isNotEmpty) {
      queryParams['aad'] = normalizedAad;
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
      Map<String, dynamic>? asMap;
      if (decoded is Map<String, dynamic>) {
        asMap = decoded;
      } else if (decoded is Map) {
        asMap = Map<String, dynamic>.from(decoded);
      }

      if (asMap != null) {
        if (cacheShardOnIOS && Platform.isIOS) {
          await _maybeCacheShard(
            payload: asMap,
            methodChannelName: methodChannelName,
            modelIdFallback: modelIdForShard ?? modelKey,
          );
        }
        return asMap;
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

  static String? _extractShard(Map<String, dynamic> payload) {
    for (final key in const [
      'kekShardB64',
      'cekShardB64',
      'keyShardB64',
      'shardB64',
      'cek_shard_b64'
    ]) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static int? _extractExpiryMs(Map<String, dynamic> payload) {
    final candidates = [
      payload['expiresAt'],
      payload['expires_at'],
      payload['expiry_epoch_ms'],
      payload['cekSecretExpiresAt'],
    ];

    for (final candidate in candidates) {
      if (candidate is int) {
        return candidate;
      }
      if (candidate is num) {
        return candidate.toInt();
      }
      if (candidate is String && candidate.isNotEmpty) {
        try {
          final parsed = DateTime.tryParse(candidate)?.toUtc();
          if (parsed != null) {
            return parsed.millisecondsSinceEpoch;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static Future<void> _maybeCacheShard({
    required Map<String, dynamic> payload,
    required String methodChannelName,
    required String modelIdFallback,
  }) async {
    final shard = _extractShard(payload);
    if (shard == null) {
      return;
    }

    final shardRequired =
        payload['shardRequired'] == true || payload['shard_required'] == true;
    if (!shardRequired && shard.isEmpty) {
      return;
    }

    final modelId = (payload['modelKey'] as String?) ?? modelIdFallback;
    if (modelId.isEmpty) {
      return;
    }

    final expiresAtMs = _extractExpiryMs(payload);
    ModelRuntime(methodChannelName);
    await ModelRuntime.setKeyShard(
      modelId: modelId,
      keyShardB64: shard,
      expiresAtMs: expiresAtMs,
    );
  }
}
