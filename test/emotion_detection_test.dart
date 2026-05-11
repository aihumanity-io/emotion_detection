import 'package:emotion_detection/emotion_detection.dart';
import 'package:emotion_detection/emotion_detection_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeEmotionDetectionPlatform
    with MockPlatformInterfaceMixin
    implements EmotionDetectionPlatform {
  String? streamModelId;
  String? previewModelId;
  var hidePreviewCallCount = 0;
  Map<String, dynamic>? savedUserCode;
  Map<String, dynamic>? clearedUserCode;
  String? configuredModelRuntimeChannel;
  Map<String, dynamic>? registeredModel;
  Map<String, dynamic>? keyShard;
  String? clearedKeyShardModelId;
  Map<String, dynamic>? modelLicense;
  String? clearedModelLicenseModelId;
  String? warmedModelId;
  Map<String, dynamic>? predictionRequest;
  String? unloadedModelId;
  Map<String, dynamic>? faceEmotionInputs;

  @override
  Future<String?> getPlatformVersion() async => '42';

  @override
  Stream<Map<String, double>> macCameraStream({String? modelId}) {
    streamModelId = modelId;
    return Stream<Map<String, double>>.value({'happy': 0.75});
  }

  @override
  Future<void> macShowCameraPreview({String? modelId}) async {
    previewModelId = modelId;
  }

  @override
  Future<void> macHideCameraPreview() async {
    hidePreviewCallCount += 1;
  }

  @override
  Future<void> saveUserCode({
    required String userName,
    required String userCodeB64,
    bool requireBiometrics = false,
    String? modelId,
  }) async {
    savedUserCode = <String, dynamic>{
      'userName': userName,
      'userCodeB64': userCodeB64,
      'requireBiometrics': requireBiometrics,
      'modelId': modelId,
    };
  }

  @override
  Future<void> clearUserCode(String userName, {String? modelId}) async {
    clearedUserCode = <String, dynamic>{
      'userName': userName,
      'modelId': modelId,
    };
  }

  @override
  void configureModelRuntimeChannel(String methodChannelName) {
    configuredModelRuntimeChannel = methodChannelName;
  }

  @override
  Future<void> registerModel({
    required String modelId,
    required String resourceBase,
    String encExt = 'onnx.enc',
    String hkdfInfo = 'model_runtime',
    String? masterKeyB64,
  }) async {
    registeredModel = <String, dynamic>{
      'modelId': modelId,
      'resourceBase': resourceBase,
      'encExt': encExt,
      'hkdfInfo': hkdfInfo,
      'masterKeyB64': masterKeyB64,
    };
  }

  @override
  Future<void> setKeyShard({
    required String modelId,
    required String keyShardB64,
    int? expiresAtMs,
    String? userName,
  }) async {
    keyShard = <String, dynamic>{
      'modelId': modelId,
      'keyShardB64': keyShardB64,
      'expiresAtMs': expiresAtMs,
      'userName': userName,
    };
  }

  @override
  Future<void> clearKeyShard(String modelId) async {
    clearedKeyShardModelId = modelId;
  }

  @override
  Future<void> setModelLicense({
    required String modelId,
    required Map<String, dynamic> license,
  }) async {
    modelLicense = <String, dynamic>{
      'modelId': modelId,
      'license': license,
    };
  }

  @override
  Future<void> clearModelLicense(String modelId) async {
    clearedModelLicenseModelId = modelId;
  }

  @override
  Future<bool> warmUp(String modelId) async {
    warmedModelId = modelId;
    return true;
  }

  @override
  Future<Map<String, dynamic>> predict(
    String modelId,
    Map<String, dynamic> inputs,
  ) async {
    predictionRequest = <String, dynamic>{
      'modelId': modelId,
      'inputs': inputs,
    };
    return <String, dynamic>{'happy': 0.5};
  }

  @override
  Future<void> unload(String modelId) async {
    unloadedModelId = modelId;
  }

  @override
  Future<Map?> faceEmotion(Map<String, dynamic> inputs) async {
    faceEmotionInputs = inputs;
    return <String, dynamic>{'Neutral': 0.8};
  }
}

class _UnimplementedFaceEmotionPlatform extends EmotionDetectionPlatform {}

void main() {
  test('getPlatformVersion delegates to platform implementation', () async {
    EmotionDetectionPlatform.instance = _FakeEmotionDetectionPlatform();

    await expectLater(
      EmotionDetection().getPlatformVersion(),
      completion('42'),
    );
  });

  test('mac camera stream delegates to platform implementation', () async {
    final platform = _FakeEmotionDetectionPlatform();
    EmotionDetectionPlatform.instance = platform;

    await expectLater(
      EmotionDetection().macCameraStream(modelId: 'model-a'),
      emits({'happy': 0.75}),
    );
    expect(platform.streamModelId, 'model-a');
  });

  test('mac camera preview controls delegate to platform implementation',
      () async {
    final platform = _FakeEmotionDetectionPlatform();
    EmotionDetectionPlatform.instance = platform;

    await EmotionDetection().macShowCameraPreview(modelId: 'model-b');
    await EmotionDetection().macHideCameraPreview();

    expect(platform.previewModelId, 'model-b');
    expect(platform.hidePreviewCallCount, 1);
  });

  test('user code channel delegates save and clear to platform implementation',
      () async {
    final platform = _FakeEmotionDetectionPlatform();
    EmotionDetectionPlatform.instance = platform;

    await UserCodeChannel.saveUserCode(
      userName: 'david',
      userCodeB64: 'code',
      requireBiometrics: true,
      modelId: 'model-c',
    );
    await UserCodeChannel.clearUserCode('david', modelId: 'model-c');

    expect(platform.savedUserCode, <String, dynamic>{
      'userName': 'david',
      'userCodeB64': 'code',
      'requireBiometrics': true,
      'modelId': 'model-c',
    });
    expect(platform.clearedUserCode, <String, dynamic>{
      'userName': 'david',
      'modelId': 'model-c',
    });
  });

  test('model runtime delegates provisioning calls to platform implementation',
      () async {
    final platform = _FakeEmotionDetectionPlatform();
    EmotionDetectionPlatform.instance = platform;

    ModelRuntime('custom_channel');
    await ModelRuntime.registerModel(
      modelId: 'model-d',
      resourceBase: 'face_v1',
      encExt: 'onnx.enc',
      hkdfInfo: 'runtime',
      masterKeyB64: 'master',
    );
    await ModelRuntime.setKeyShard(
      modelId: 'model-d',
      keyShardB64: 'shard',
      expiresAtMs: 123,
      userName: 'david',
    );
    await ModelRuntime.setModelLicense(
      modelId: 'model-d',
      license: <String, dynamic>{'ok': true},
    );

    expect(platform.configuredModelRuntimeChannel, 'custom_channel');
    expect(platform.registeredModel, <String, dynamic>{
      'modelId': 'model-d',
      'resourceBase': 'face_v1',
      'encExt': 'onnx.enc',
      'hkdfInfo': 'runtime',
      'masterKeyB64': 'master',
    });
    expect(platform.keyShard, <String, dynamic>{
      'modelId': 'model-d',
      'keyShardB64': 'shard',
      'expiresAtMs': 123,
      'userName': 'david',
    });
    expect(platform.modelLicense, <String, dynamic>{
      'modelId': 'model-d',
      'license': <String, dynamic>{'ok': true},
    });
  });

  test(
      'model runtime delegates prediction lifecycle to platform implementation',
      () async {
    final platform = _FakeEmotionDetectionPlatform();
    EmotionDetectionPlatform.instance = platform;

    final warmed = await ModelRuntime.warmUp('model-e');
    final prediction = await ModelRuntime.predict(
      'model-e',
      <String, dynamic>{'input': 1},
    );
    await ModelRuntime.clearKeyShard('model-e');
    await ModelRuntime.clearModelLicense('model-e');
    await ModelRuntime.unload('model-e');

    expect(warmed, isTrue);
    expect(prediction, <String, dynamic>{'happy': 0.5});
    expect(platform.warmedModelId, 'model-e');
    expect(platform.predictionRequest, <String, dynamic>{
      'modelId': 'model-e',
      'inputs': <String, dynamic>{'input': 1},
    });
    expect(platform.clearedKeyShardModelId, 'model-e');
    expect(platform.clearedModelLicenseModelId, 'model-e');
    expect(platform.unloadedModelId, 'model-e');
  });

  test('face emotion inference delegates to platform implementation', () async {
    final platform = _FakeEmotionDetectionPlatform();
    EmotionDetectionPlatform.instance = platform;

    final result = await EmotionDetectionPlatform.instance.faceEmotion(
      <String, dynamic>{
        'faceImageData': <int>[1, 2, 3]
      },
    );

    expect(result, <String, dynamic>{'Neutral': 0.8});
    expect(platform.faceEmotionInputs, <String, dynamic>{
      'faceImageData': <int>[1, 2, 3],
    });
  });

  test('face emotion fails clearly when a platform has not implemented it',
      () async {
    EmotionDetectionPlatform.instance = _UnimplementedFaceEmotionPlatform();

    expect(
      () => EmotionDetectionPlatform.instance.faceEmotion(<String, dynamic>{}),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
