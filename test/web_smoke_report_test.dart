import 'package:emotion_detection/emotion_detection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web smoke report serializes required browser fields', () {
    final report = WebSmokeReport(
      origin: 'https://app.example',
      browser: 'Chrome',
      firstPaintMs: 10,
      cameraPermissionMs: 20,
      firstFrameMs: 30,
      inferenceRoundTripMs: 40,
      responseLabels: const ['Neutral', 'Happiness'],
      assetAuditPassed: true,
    );

    expect(report.passed, isTrue);
    expect(report.toJson(), <String, dynamic>{
      'origin': 'https://app.example',
      'browser': 'Chrome',
      'firstPaintMs': 10,
      'cameraPermissionMs': 20,
      'firstFrameMs': 30,
      'inferenceRoundTripMs': 40,
      'responseLabels': <String>['Neutral', 'Happiness'],
      'assetAuditPassed': true,
      'passed': true,
    });
  });

  test('web smoke report parses json artifacts', () {
    final report = WebSmokeReport.fromJson(<String, dynamic>{
      'origin': 'http://localhost:8080',
      'browser': 'Chrome',
      'firstPaintMs': 1,
      'cameraPermissionMs': 2,
      'firstFrameMs': 3,
      'inferenceRoundTripMs': 4,
      'responseLabels': <String>['Neutral'],
      'assetAuditPassed': true,
    });

    expect(report.origin, 'http://localhost:8080');
    expect(report.responseLabels, <String>['Neutral']);
    expect(report.passed, isTrue);
  });

  test('web smoke report rejects malformed artifacts', () {
    expect(
      () => WebSmokeReport(
        origin: '',
        browser: 'Chrome',
        firstPaintMs: 1,
        cameraPermissionMs: 2,
        firstFrameMs: 3,
        inferenceRoundTripMs: 4,
        responseLabels: const ['Neutral'],
        assetAuditPassed: true,
      ),
      throwsA(isA<WebSmokeReportException>()),
    );
    expect(
      () => WebSmokeReport.fromJson(<String, dynamic>{
        'origin': 'http://localhost:8080',
        'browser': 'Chrome',
        'firstPaintMs': -1,
        'cameraPermissionMs': 2,
        'firstFrameMs': 3,
        'inferenceRoundTripMs': 4,
        'responseLabels': <String>['Neutral'],
        'assetAuditPassed': true,
      }),
      throwsA(isA<WebSmokeReportException>()),
    );
  });
}
