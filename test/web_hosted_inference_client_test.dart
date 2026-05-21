import 'dart:convert';

import 'package:emotion_detection/emotion_detection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('client sends required request metadata without secrets', () async {
    late http.Request captured;
    final client = WebHostedInferenceClient(
      baseUri: Uri.parse('https://example.test'),
      publishableKey: 'pk_test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'requestId': 'req-1',
            'modelId': 'model-a',
            'scores': <String, double>{'Neutral': 0.8, 'Happiness': 0.2},
            'topLabel': 'Neutral',
            'timingMs': <String, double>{
              'preprocess': 1,
              'inference': 2,
              'total': 3,
            },
          }),
          200,
        );
      }),
    );

    final result = await client.infer(_request());
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;

    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'https://example.test/sdk/web/infer');
    expect(captured.headers['X-SDK-Publishable-Key'], 'pk_test');
    expect(captured.headers.containsKey('Authorization'), isFalse);
    expect(payload['requestId'], 'req-1');
    expect(payload['modelId'], 'model-a');
    expect(payload['source'], 'camera');
    expect(payload['client'], <String, dynamic>{
      'sdkVersion': '0.2.0',
      'platform': 'web',
      'origin': 'https://app.example',
    });
    expect(payload.toString(), isNot(contains('sdkSecret')));
    expect(payload.toString(), isNot(contains('userCode')));
    expect(payload.toString(), isNot(contains('keyShard')));
    expect(result.topLabel, 'Neutral');
    expect(result.roundTripMs, isNonNegative);
  });

  test('client can authenticate with a short-lived session token', () async {
    late http.Request captured;
    final client = WebHostedInferenceClient(
      baseUri: Uri.parse('https://example.test/base'),
      sessionToken: 'session-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'requestId': 'req-1',
            'modelId': 'model-a',
            'scores': <String, double>{'Neutral': 1.0},
            'topLabel': 'Neutral',
            'timingMs': <String, double>{
              'preprocess': 1,
              'inference': 2,
              'total': 3,
            },
          }),
          200,
        );
      }),
    );

    await client.infer(_request());

    expect(captured.url.toString(), 'https://example.test/base/sdk/web/infer');
    expect(captured.headers['Authorization'], 'Bearer session-token');
    expect(captured.headers.containsKey('X-SDK-Publishable-Key'), isFalse);
  });

  test('client validates score response shape', () async {
    final client = WebHostedInferenceClient(
      baseUri: Uri.parse('https://example.test'),
      publishableKey: 'pk_test',
      httpClient: MockClient((_) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'requestId': 'req-1',
            'modelId': 'model-a',
            'scores': <String, double>{'Neutral': 0.4},
            'topLabel': 'Happiness',
            'timingMs': <String, double>{
              'preprocess': 1,
              'inference': 2,
              'total': 3,
            },
          }),
          200,
        );
      }),
    );

    expect(
      () => client.infer(_request()),
      throwsA(isA<WebHostedInferenceException>()),
    );
  });

  test('client surfaces structured server errors', () async {
    final client = WebHostedInferenceClient(
      baseUri: Uri.parse('https://example.test'),
      publishableKey: 'pk_test',
      httpClient: MockClient((_) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'code': 'invalid_image',
            'message': 'image is too large',
          }),
          413,
        );
      }),
    );

    expect(
      () => client.infer(_request()),
      throwsA(
        isA<WebHostedInferenceException>()
            .having((error) => error.code, 'code', 'invalid_image')
            .having((error) => error.statusCode, 'statusCode', 413),
      ),
    );
  });

  test('request validation rejects malformed image and source inputs', () {
    expect(
      () => _request(
        image: const WebHostedInferenceImage(
          format: 'bmp',
          dataB64: 'abc',
          width: 32,
          height: 32,
        ),
      ).toJson(),
      throwsA(isA<WebHostedInferenceException>()),
    );
    expect(
      () => _request(source: 'full_model').toJson(),
      throwsA(isA<WebHostedInferenceException>()),
    );
  });
}

WebHostedInferenceRequest _request({
  WebHostedInferenceImage image = const WebHostedInferenceImage(
    format: 'jpeg',
    dataB64: 'abc',
    width: 32,
    height: 32,
  ),
  String source = 'camera',
}) {
  return WebHostedInferenceRequest(
    requestId: 'req-1',
    modelId: 'model-a',
    image: image,
    source: source,
    sdkVersion: '0.2.0',
    origin: 'https://app.example',
    faceBox: const WebHostedInferenceFaceBox(
      left: 1,
      top: 2,
      width: 24,
      height: 24,
    ),
    debug: true,
  );
}
