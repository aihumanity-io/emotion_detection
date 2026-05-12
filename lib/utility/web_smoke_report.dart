class WebSmokeReportException implements Exception {
  WebSmokeReportException(this.message);

  final String message;

  @override
  String toString() => 'WebSmokeReportException: $message';
}

class WebSmokeReport {
  WebSmokeReport({
    required this.origin,
    required this.browser,
    required this.firstPaintMs,
    required this.cameraPermissionMs,
    required this.firstFrameMs,
    required this.inferenceRoundTripMs,
    required this.responseLabels,
    required this.assetAuditPassed,
  }) {
    _validate();
  }

  final String origin;
  final String browser;
  final int firstPaintMs;
  final int cameraPermissionMs;
  final int firstFrameMs;
  final int inferenceRoundTripMs;
  final List<String> responseLabels;
  final bool assetAuditPassed;

  bool get passed => assetAuditPassed && responseLabels.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'origin': origin,
        'browser': browser,
        'firstPaintMs': firstPaintMs,
        'cameraPermissionMs': cameraPermissionMs,
        'firstFrameMs': firstFrameMs,
        'inferenceRoundTripMs': inferenceRoundTripMs,
        'responseLabels': responseLabels,
        'assetAuditPassed': assetAuditPassed,
        'passed': passed,
      };

  static WebSmokeReport fromJson(Map<String, dynamic> json) {
    final labels = json['responseLabels'];
    if (labels is! List) {
      throw WebSmokeReportException('responseLabels must be a list.');
    }
    return WebSmokeReport(
      origin: _readString(json, 'origin'),
      browser: _readString(json, 'browser'),
      firstPaintMs: _readNonNegativeInt(json, 'firstPaintMs'),
      cameraPermissionMs: _readNonNegativeInt(json, 'cameraPermissionMs'),
      firstFrameMs: _readNonNegativeInt(json, 'firstFrameMs'),
      inferenceRoundTripMs: _readNonNegativeInt(
        json,
        'inferenceRoundTripMs',
      ),
      responseLabels: labels.map((label) => label.toString()).toList(),
      assetAuditPassed: _readBool(json, 'assetAuditPassed'),
    );
  }

  void _validate() {
    if (origin.trim().isEmpty || browser.trim().isEmpty) {
      throw WebSmokeReportException('origin and browser are required.');
    }
    for (final entry in <String, int>{
      'firstPaintMs': firstPaintMs,
      'cameraPermissionMs': cameraPermissionMs,
      'firstFrameMs': firstFrameMs,
      'inferenceRoundTripMs': inferenceRoundTripMs,
    }.entries) {
      if (entry.value < 0) {
        throw WebSmokeReportException('${entry.key} must be non-negative.');
      }
    }
    if (responseLabels.any((label) => label.trim().isEmpty)) {
      throw WebSmokeReportException('responseLabels cannot contain blanks.');
    }
  }
}

String _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw WebSmokeReportException('$key is required.');
}

int _readNonNegativeInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) {
    return value;
  }
  throw WebSmokeReportException('$key must be a non-negative integer.');
}

bool _readBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw WebSmokeReportException('$key must be a boolean.');
}
