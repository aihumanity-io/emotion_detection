import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:emotion_detection/emotion_detection.dart';
import 'package:emotion_detection/native/model_runtime.dart';
import 'package:emotion_detection/native/user_code_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sdk_secret_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cams = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _emotionDetectionPlugin = EmotionDetection();
  EmotionDetectorViewController controller = EmotionDetectorViewController();
  final ExampleSdkSecretModule _sdkSecretModule = ExampleSdkSecretModule();
  static const _methodChannelName = 'face_emotion_detection';
  String _cekSecretStatus = 'Not requested yet.';
  bool _fetchingCekSecret = false;
  bool _userCodeReady = false;
  static const bool _kOneTimeClearCaches = false;
  bool _didClearCaches = false;

  static Map<String, String> _modelAccountIds = {
    'aih_fer20250115': 'aih_fer20250115_v2025-01-15-shard',
    'mobilenetv1_fer2024-11-06-08-48-50':
        'mobilenetv1_fer2024-11-06-08-48-50_v2025-01-15-shard',
  };

  String _accountModelId(String modelKey) =>
      _modelAccountIds[modelKey] ?? modelKey;

  Iterable<String> _allModelIds(String modelKey) sync* {
    yield modelKey;
    final mapped = _modelAccountIds[modelKey];
    if (mapped != null && mapped.isNotEmpty && mapped != modelKey) {
      yield mapped;
    }
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _modelAccountIds = {
        'mobilenetv1_fer2024-11-06-08-48-50':
            'mobilenetv1_fer2024-11-06-08-48-50',
      };
    }

    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion = await _emotionDetectionPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  void _ensureModelRuntimeChannel() {
    ModelRuntime(_methodChannelName);
  }

  Future<void> _maybeClearCaches() async {
    if (!_kOneTimeClearCaches || _didClearCaches) return;
    _didClearCaches = true;
    _ensureModelRuntimeChannel();
    for (final modelKey in _sdkSecretModule.modelKeys) {
      final accountId = _accountModelId(modelKey);
      try {
        await UserCodeChannel.clearUserCode(
          _sdkSecretModule.userName,
          modelId: accountId,
        );
      } catch (error) {
        debugPrint('Clear user code failed for $modelKey: $error');
      }
      try {
        await ModelRuntime.clearKeyShard(modelKey);
      } catch (error) {
        debugPrint('Clear shard failed for $modelKey: $error');
      }
    }
    try {
      // Also clear legacy account without modelId to avoid collisions.
      await UserCodeChannel.clearUserCode(_sdkSecretModule.userName);
    } catch (error) {
      debugPrint('Clear legacy user code failed: $error');
    }
  }

  Future<void> _fetchCekSecret() async {
    await _maybeClearCaches();
    if (!_sdkSecretModule.hasRequiredConfig) {
      setState(() {
        _cekSecretStatus =
            'Missing EXAMPLE_SDK_* dart-defines. Update run configs to call the endpoint.';
      });
      return;
    }

    setState(() {
      _fetchingCekSecret = true;
      _cekSecretStatus = 'Requesting /sdk/cek-secret...';
    });
    final aad = _sdkSecretModule.aadForPlatform(defaultTargetPlatform);
    final keys = _sdkSecretModule.modelKeysForPlatform(defaultTargetPlatform);
    final results = await _sdkSecretModule.fetchAllCekSecrets(
      aadOverride: aad,
      modelKeys: keys,
    );
    String status = 'fetchCekSecret returned null (see logs).';
    if (results.isNotEmpty) {
      status = 'Received ${results.length} response(s)';
      for (final res in results) {
        if (kDebugMode) {
          debugPrint('CEK secret response: ${res.payload}');
        }
      }

      int storedUserCodes = 0;
      int shardCount = 0;

      if (!_sdkSecretModule.hasUserName) {
        status = 'Missing EXAMPLE_USER_NAME to save user code.';
      } else {
        try {
          _ensureModelRuntimeChannel();

          for (final res in results) {
            final modelKey = res.modelKey;
            if (defaultTargetPlatform == TargetPlatform.android &&
                modelKey == 'aih_fer20250115') {
              // skip models not supported on Android yet
              continue;
            }
            final accountId = _accountModelId(modelKey);
            final userCodeB64 = _sdkSecretModule.extractUserCode(res.payload);
            if (userCodeB64 != null) {
              try {
                if (kDebugMode) {
                  debugPrint(
                      'Storing user code for $modelKey len=${userCodeB64.length} b64prefix=${userCodeB64.substring(0, math.min(8, userCodeB64.length))}');
                }
                await UserCodeChannel.saveUserCode(
                  userName: _sdkSecretModule.userName,
                  userCodeB64: userCodeB64,
                  modelId: accountId,
                );
                storedUserCodes++;
              } catch (error) {
                debugPrint('saveUserCode failed for $modelKey: $error');
              }
            }
            if (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android) {
              final shardB64 = _sdkSecretModule.extractShard(
                res.payload,
                modelKey: modelKey,
              );
              final expiresAtMs = _sdkSecretModule.extractExpiresAtMs(
                res.payload,
                modelKey: modelKey,
              );
              if (shardB64 != null) {
                try {
                  if (kDebugMode) {
                    debugPrint(
                        'Storing shard for $modelKey len=${shardB64.length} b64prefix=${shardB64.substring(0, math.min(8, shardB64.length))} exp=$expiresAtMs');
                  }
                  for (final id in _allModelIds(modelKey)) {
                    await ModelRuntime.setKeyShard(
                      modelId: id,
                      keyShardB64: _sdkSecretModule.normalizeShard(shardB64),
                      expiresAtMs: expiresAtMs,
                    );
                  }
                  shardCount++;
                } catch (error) {
                  debugPrint('setKeyShard failed for $modelKey: $error');
                }
              }
            }
          }

          _userCodeReady = storedUserCodes > 0;
          if (storedUserCodes == 0) {
            status = 'Responses missing userCodeB64 field.';
          } else {
            status = shardCount > 0
                ? 'User codes stored ($storedUserCodes); shards stored ($shardCount/${results.length})'
                : 'User codes stored ($storedUserCodes); no shards in responses.';
          }
        } catch (error) {
          status = 'Failed to store user code/shard: $error';
          _userCodeReady = false;
        }
      }
    }

    setState(() {
      _fetchingCekSecret = false;
      _cekSecretStatus = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: _userCodeReady
            ? EmotionDetectorView(controller: controller)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(
                        _cekSecretStatus,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _fetchingCekSecret ? null : _fetchCekSecret,
                        child: Text(
                          _fetchingCekSecret
                              ? 'Fetching SDK secret...'
                              : 'Fetch SDK CEK secret',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
