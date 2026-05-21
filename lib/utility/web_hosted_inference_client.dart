import 'dart:convert';

import 'package:http/http.dart' as http;

const String webHostedInferencePath = '/sdk/web/infer';

class WebHostedInferenceException implements Exception {
  WebHostedInferenceException(
    this.code,
    this.message, {
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'WebHostedInferenceException($code, statusCode: $statusCode): $message';
}

class WebHostedInferenceFaceBox {
  const WebHostedInferenceFaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };
}

class WebHostedInferenceImage {
  const WebHostedInferenceImage({
    required this.format,
    required this.dataB64,
    required this.width,
    required this.height,
    this.colorSpace = 'srgb',
  });

  final String format;
  final String dataB64;
  final int width;
  final int height;
  final String colorSpace;

  Map<String, dynamic> toJson() {
    final normalizedFormat = format.trim().toLowerCase();
    if (normalizedFormat != 'jpeg' && normalizedFormat != 'png') {
      throw WebHostedInferenceException(
        'invalid_image_format',
        'image.format must be jpeg or png.',
      );
    }
    if (dataB64.trim().isEmpty) {
      throw WebHostedInferenceException(
        'missing_image_data',
        'image.dataB64 is required.',
      );
    }
    if (width <= 0 || height <= 0) {
      throw WebHostedInferenceException(
        'invalid_image_size',
        'image width and height must be positive.',
      );
    }

    return <String, dynamic>{
      'format': normalizedFormat,
      'dataB64': dataB64,
      'width': width,
      'height': height,
      'colorSpace': colorSpace,
    };
  }
}

class WebHostedInferenceRequest {
  const WebHostedInferenceRequest({
    required this.requestId,
    required this.modelId,
    required this.image,
    required this.source,
    required this.sdkVersion,
    required this.origin,
    this.faceBox,
    this.debug = false,
  });

  final String requestId;
  final String modelId;
  final WebHostedInferenceImage image;
  final String source;
  final String sdkVersion;
  final String origin;
  final WebHostedInferenceFaceBox? faceBox;
  final bool debug;

  Map<String, dynamic> toJson() {
    final normalizedSource = source.trim().toLowerCase();
    if (requestId.trim().isEmpty) {
      throw WebHostedInferenceException(
        'missing_request_id',
        'requestId is required.',
      );
    }
    if (modelId.trim().isEmpty) {
      throw WebHostedInferenceException(
        'missing_model_id',
        'modelId is required.',
      );
    }
    if (!const {'camera', 'upload', 'test_fixture'}
        .contains(normalizedSource)) {
      throw WebHostedInferenceException(
        'invalid_source',
        'source must be camera, upload, or test_fixture.',
      );
    }
    if (sdkVersion.trim().isEmpty || origin.trim().isEmpty) {
      throw WebHostedInferenceException(
        'missing_client_metadata',
        'client.sdkVersion and client.origin are required.',
      );
    }

    return <String, dynamic>{
      'requestId': requestId,
      'modelId': modelId,
      'image': image.toJson(),
      'source': normalizedSource,
      'client': <String, dynamic>{
        'sdkVersion': sdkVersion,
        'platform': 'web',
        'origin': origin,
      },
      if (faceBox != null) 'faceBox': faceBox!.toJson(),
      if (debug) 'debug': true,
    };
  }
}

class WebHostedInferenceTiming {
  const WebHostedInferenceTiming({
    required this.preprocess,
    required this.inference,
    required this.total,
  });

  final double preprocess;
  final double inference;
  final double total;

  static WebHostedInferenceTiming fromJson(Map<String, dynamic> json) {
    return WebHostedInferenceTiming(
      preprocess: _readFiniteNumber(json, 'preprocess'),
      inference: _readFiniteNumber(json, 'inference'),
      total: _readFiniteNumber(json, 'total'),
    );
  }
}

class WebHostedInferenceResult {
  const WebHostedInferenceResult({
    required this.requestId,
    required this.modelId,
    required this.scores,
    required this.topLabel,
    required this.timingMs,
    required this.roundTripMs,
  });

  final String requestId;
  final String modelId;
  final Map<String, double> scores;
  final String topLabel;
  final WebHostedInferenceTiming timingMs;
  final int roundTripMs;

  static WebHostedInferenceResult fromJson(
    Map<String, dynamic> json, {
    required int roundTripMs,
  }) {
    final requestId = _readString(json, 'requestId');
    final modelId = _readString(json, 'modelId');
    final topLabel = _readString(json, 'topLabel');
    final rawScores = json['scores'];
    final rawTiming = json['timingMs'];
    if (rawScores is! Map) {
      throw WebHostedInferenceException(
        'invalid_scores',
        'scores must be a label-to-score map.',
      );
    }
    if (rawTiming is! Map) {
      throw WebHostedInferenceException(
        'invalid_timing',
        'timingMs must be an object.',
      );
    }

    final scores = <String, double>{};
    var sum = 0.0;
    rawScores.forEach((key, value) {
      final label = key.toString();
      if (label.isEmpty || value is! num || !value.toDouble().isFinite) {
        throw WebHostedInferenceException(
          'invalid_score',
          'scores must contain non-empty labels and finite numeric values.',
        );
      }
      final score = value.toDouble();
      if (score < 0.0 || score > 1.0) {
        throw WebHostedInferenceException(
          'invalid_score',
          'scores must be between 0.0 and 1.0.',
        );
      }
      scores[label] = score;
      sum += score;
    });

    if (scores.isEmpty || !scores.containsKey(topLabel)) {
      throw WebHostedInferenceException(
        'invalid_top_label',
        'topLabel must exist in scores.',
      );
    }
    if ((sum - 1.0).abs() > 0.01) {
      throw WebHostedInferenceException(
        'invalid_score_sum',
        'score sum must be within 0.01 of 1.0.',
      );
    }

    return WebHostedInferenceResult(
      requestId: requestId,
      modelId: modelId,
      scores: Map<String, double>.unmodifiable(scores),
      topLabel: topLabel,
      timingMs: WebHostedInferenceTiming.fromJson(
        Map<String, dynamic>.from(rawTiming),
      ),
      roundTripMs: roundTripMs,
    );
  }
}

class WebHostedInferenceClient {
  WebHostedInferenceClient({
    required this.baseUri,
    required this.httpClient,
    this.publishableKey,
    this.sessionToken,
  }) {
    if ((publishableKey == null || publishableKey!.trim().isEmpty) &&
        (sessionToken == null || sessionToken!.trim().isEmpty)) {
      throw WebHostedInferenceException(
        'missing_auth',
        'publishableKey or sessionToken is required.',
      );
    }
  }

  final Uri baseUri;
  final http.Client httpClient;
  final String? publishableKey;
  final String? sessionToken;

  Future<WebHostedInferenceResult> infer(
    WebHostedInferenceRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();
    final response = await httpClient.post(
      _endpointUri(),
      headers: _headers(),
      body: jsonEncode(request.toJson()),
    );
    stopwatch.stop();

    final decoded = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = decoded['code']?.toString() ?? 'hosted_inference_error';
      final message = decoded['message']?.toString() ?? response.body;
      throw WebHostedInferenceException(
        code,
        message,
        statusCode: response.statusCode,
      );
    }

    return WebHostedInferenceResult.fromJson(
      decoded,
      roundTripMs: stopwatch.elapsedMilliseconds,
    );
  }

  Uri _endpointUri() {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$basePath$webHostedInferencePath');
  }

  Map<String, String> _headers() {
    return <String, String>{
      'Content-Type': 'application/json',
      if (sessionToken != null && sessionToken!.trim().isNotEmpty)
        'Authorization': 'Bearer ${sessionToken!.trim()}'
      else
        'X-SDK-Publishable-Key': publishableKey!.trim(),
    };
  }
}

Map<String, dynamic> _decodeJsonObject(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  throw WebHostedInferenceException(
    'invalid_response',
    'response body must be a JSON object.',
  );
}

String _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw WebHostedInferenceException(
    'missing_$key',
    '$key is required.',
  );
}

double _readFiniteNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num && value.toDouble().isFinite) {
    return value.toDouble();
  }
  throw WebHostedInferenceException(
    'invalid_$key',
    '$key must be a finite number.',
  );
}
