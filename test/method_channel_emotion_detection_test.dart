import 'package:emotion_detection/emotion_detection_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const defaultChannel = MethodChannel('face_emotion_detection');
  const runtimeChannel = MethodChannel('custom_runtime_channel');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(defaultChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(runtimeChannel, null);
  });

  test('mac camera preview methods use the default platform channel', () async {
    final platform = MethodChannelEmotionDetection();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(defaultChannel, (call) async {
      calls.add(call);
      return null;
    });

    await platform.macShowCameraPreview(modelId: 'model-a');
    await platform.macHideCameraPreview();

    expect(calls, hasLength(2));
    expect(calls[0].method, 'showMacCameraPreview');
    expect(calls[0].arguments, <String, dynamic>{'modelId': 'model-a'});
    expect(calls[1].method, 'hideMacCameraPreview');
    expect(calls[1].arguments, isNull);
  });

  test('user code methods send exact platform channel payloads', () async {
    final platform = MethodChannelEmotionDetection();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(defaultChannel, (call) async {
      calls.add(call);
      return null;
    });

    await platform.saveUserCode(
      userName: 'david',
      userCodeB64: 'code',
      requireBiometrics: true,
      modelId: 'model-b',
    );
    await platform.clearUserCode('david', modelId: 'model-b');

    expect(calls, hasLength(2));
    expect(calls[0].method, 'setUserCode');
    expect(calls[0].arguments, <String, dynamic>{
      'userName': 'david',
      'userCodeB64': 'code',
      'requireBiometrics': true,
      'modelId': 'model-b',
    });
    expect(calls[1].method, 'clearUserCode');
    expect(calls[1].arguments, <String, dynamic>{
      'userName': 'david',
      'modelId': 'model-b',
    });
  });

  test('model runtime methods use configured channel and typed outputs',
      () async {
    final platform = MethodChannelEmotionDetection()
      ..configureModelRuntimeChannel('custom_runtime_channel');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(runtimeChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'warmUp':
          return true;
        case 'predict':
          return <String, dynamic>{'happy': 0.9};
      }
      return null;
    });

    await platform.registerModel(
      modelId: 'model-c',
      resourceBase: 'face_v1',
      hkdfInfo: 'runtime',
      masterKeyB64: 'master',
    );
    await platform.setKeyShard(
      modelId: 'model-c',
      keyShardB64: 'shard',
      expiresAtMs: 123,
      userName: 'david',
    );
    await platform.setModelLicense(
      modelId: 'model-c',
      license: <String, dynamic>{'ok': true},
    );
    final warmed = await platform.warmUp('model-c');
    final prediction = await platform.predict(
      'model-c',
      <String, dynamic>{'input': 1},
    );
    await platform.clearKeyShard('model-c');
    await platform.clearModelLicense('model-c');
    await platform.unload('model-c');

    expect(warmed, isTrue);
    expect(prediction, <String, dynamic>{'happy': 0.9});
    expect(calls.map((call) => call.method), <String>[
      'registerModel',
      'setKeyShard',
      'setModelLicense',
      'warmUp',
      'predict',
      'clearKeyShard',
      'clearModelLicense',
      'unload',
    ]);
    expect(calls[0].arguments, <String, dynamic>{
      'modelId': 'model-c',
      'resourceBase': 'face_v1',
      'encExt': 'onnx.enc',
      'hkdfInfo': 'runtime',
      'masterKeyB64': 'master',
    });
    expect(calls[1].arguments, <String, dynamic>{
      'modelId': 'model-c',
      'keyShardB64': 'shard',
      'expiresAtMs': 123,
      'userName': 'david',
    });
    expect(calls[2].arguments, <String, dynamic>{
      'modelId': 'model-c',
      'license': <String, dynamic>{'ok': true},
    });
    expect(calls[4].arguments, <String, dynamic>{
      'modelId': 'model-c',
      'inputs': <String, dynamic>{'input': 1},
    });
  });

  test('face emotion sends exact platform channel payload', () async {
    final platform = MethodChannelEmotionDetection();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(defaultChannel, (call) async {
      calls.add(call);
      return <String, dynamic>{'Neutral': 0.8};
    });

    final result = await platform.faceEmotion(<String, dynamic>{
      'faceImageData': <int>[1, 2, 3],
      'width': 48,
      'height': 48,
    });

    expect(result, <String, dynamic>{'Neutral': 0.8});
    expect(calls, hasLength(1));
    expect(calls.single.method, 'faceEmotion');
    expect(calls.single.arguments, <String, dynamic>{
      'faceImageData': <int>[1, 2, 3],
      'width': 48,
      'height': 48,
    });
  });
}
