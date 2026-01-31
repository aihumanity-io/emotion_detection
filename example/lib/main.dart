import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:emotion_detection/emotion_detection.dart';
import 'package:emotion_detection/native/model_runtime.dart';
import 'package:emotion_detection/native/user_code_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:typed_data';

import 'sdk_secret_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load optional .env for local SDK keys (macOS/desktop-friendly)
  try { await dotenv.load(fileName: '.env'); } catch (_) {}
  // Guard camera warm-up on desktop/web to avoid MissingPluginException.
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await availableCameras();
    } catch (_) {
      // Ignore; the widget will handle camera init later.
    }
  }
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
  late final ExampleSdkSecretModule _sdkSecretModule;
  static const _methodChannelName = 'face_emotion_detection';
  String _cekSecretStatus = 'Not requested yet.';
  bool _fetchingCekSecret = false;
  bool _userCodeReady = false;
  bool _modelsReady = false;
  bool _initializingModels = false;
  String _modelInitStatus = 'Waiting for user code to initialize models.';
  static const bool _kOneTimeClearCaches = false;
  bool _didClearCaches = false;
  String? _macResult;
  StreamSubscription<Map<String, double>>? _macCamSub;

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
    // Initialize secrets module from .env or process env if present
    final env = dotenv.env;
    final procEnv = Platform.environment;
    final apiKeyId = (env['SDK_KEY_ID'] ?? procEnv['SDK_KEY_ID'] ?? '').trim();
    final apiKeySecret = (env['SDK_KEY_SECRET'] ?? procEnv['SDK_KEY_SECRET'] ?? '').trim();
    final baseUrl = (env['EXAMPLE_SERVER_BASE_URL'] ?? procEnv['EXAMPLE_SERVER_BASE_URL'] ?? '').trim();
    final userName = (env['EXAMPLE_USER_NAME'] ?? procEnv['EXAMPLE_USER_NAME'] ?? '').trim();
    final modelKey = (env['EXAMPLE_MODEL_KEY'] ?? procEnv['EXAMPLE_MODEL_KEY'] ?? '').trim();
    final aad = (env['EXAMPLE_MODEL_AAD'] ?? procEnv['EXAMPLE_MODEL_AAD'] ?? '').trim();
    final aadAndroid = (env['EXAMPLE_MODEL_AAD_ANDROID'] ?? procEnv['EXAMPLE_MODEL_AAD_ANDROID'] ?? '').trim();
    final aadMac = (env['EXAMPLE_MODEL_AAD_MACOS'] ?? procEnv['EXAMPLE_MODEL_AAD_MACOS'] ?? '').trim();

    _sdkSecretModule = ExampleSdkSecretModule(
      apiKeyId: apiKeyId.isEmpty ? null : apiKeyId,
      apiKeySecret: apiKeySecret.isEmpty ? null : apiKeySecret,
      overrideBaseUrl: baseUrl.isEmpty ? null : baseUrl,
      userName: userName.isEmpty ? null : userName,
      modelKey: modelKey.isEmpty ? null : modelKey,
      aad: aad.isEmpty ? null : aad,
      macAad: aadMac.isEmpty ? null : aadMac,
      androidAad: aadAndroid.isEmpty ? null : aadAndroid,
    );
    if (Platform.isAndroid) {
      _modelAccountIds = {
        'mobilenetv1_fer2024-11-06-08-48-50':
            'mobilenetv1_fer2024-11-06-08-48-50',
      };
    }

    initPlatformState();
    // Automatically fetch CEK secret on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchCekSecret();
    });
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

  Future<void> _initializeModelsIfReady() async {
    if (!_userCodeReady || _modelsReady || _initializingModels) {
      return;
    }
    if (mounted) {
      setState(() {
        _initializingModels = true;
        _modelInitStatus = 'Initializing models...';
      });
    }

    try {
      _ensureModelRuntimeChannel();
      final modelIds = _sdkSecretModule
          .modelKeysForPlatform(defaultTargetPlatform)
          .where((key) {
            if (defaultTargetPlatform == TargetPlatform.android &&
                key == 'aih_fer20250115') {
              return false;
            }
            return true;
          })
          .expand((key) => _allModelIds(key))
          .toSet();

      if (defaultTargetPlatform == TargetPlatform.android) {
        for (final modelId in modelIds) {
          try {
            final warmed = await ModelRuntime.warmUp(modelId);
            if (kDebugMode) {
              debugPrint('Warm-up complete for $modelId: $warmed');
            }
          } catch (error) {
            debugPrint('Warm-up failed for $modelId: $error');
            rethrow;
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint(
              'Skipping warm-up on $defaultTargetPlatform; not supported.');
        }
      }

      _modelsReady = true;
      _modelInitStatus = 'Models ready';
    } catch (error) {
      _modelInitStatus = 'Model init failed: $error';
      _modelsReady = false;
    } finally {
      if (mounted) {
        setState(() {
          _initializingModels = false;
        });
      }
    }
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
            'Missing SDK_KEY_ID/SDK_KEY_SECRET. Provide via .env, environment, or --dart-define.';
      });
      return;
    }

    setState(() {
      _fetchingCekSecret = true;
      _cekSecretStatus = 'Requesting /sdk/cek-secret...';
      _modelsReady = false;
      _modelInitStatus = 'Waiting for user code to initialize models.';
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
            final userCodeB64 = _sdkSecretModule.extractUserCode(res.payload,
                modelKey: modelKey);
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
                defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.macOS) {
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
                      keyShardB64: shardB64,
                      expiresAtMs: expiresAtMs,
                      userName: _sdkSecretModule.userName,
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
            await _initializeModelsIfReady();
          }
        } catch (error) {
          status = 'Failed to store user code/shard: $error';
          _userCodeReady = false;
          _modelsReady = false;
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
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final body = !isMobile
        ? _buildMacDesktopDemo()
        : (!_userCodeReady
            ? _buildUserCodeWaiting()
            : (_modelsReady
                ? EmotionDetectorView(controller: controller)
                : _buildModelInit()));
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Emotion SDK Example'),
        ),
        body: body,
      ),
    );
  }

  Widget _buildMacDesktopDemo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _userCodeReady
                  ? 'User code ready. Select an image to run the model.'
                  : _cekSecretStatus,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _userCodeReady ? _pickAndPredictOnMac : null,
                  child: const Text('Select image'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _userCodeReady && _macCamSub == null ? _startMacCamera : null,
                  child: const Text('Start camera'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _macCamSub != null ? _stopMacCamera : null,
                  child: const Text('Stop camera'),
                ),
              ],
            ),
            if (_macResult != null) ...[
              const SizedBox(height: 12),
              Text('Result: $_macResult', textAlign: TextAlign.center),
            ]
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndPredictOnMac() async {
    try {
      final typeGroup = const XTypeGroup(label: 'images', extensions: ['png', 'jpg', 'jpeg']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      _ensureModelRuntimeChannel();
      final modelId = 'mobilenetv1_fer2024-11-06-08-48-50';
      final out = await ModelRuntime.predict(modelId, { 'imageBytes': bytes });
      if (out.isEmpty) {
        setState(() { _macResult = 'No output'; });
        return;
      }
      // Find top label
      String best = '';
      double bestV = -1.0;
      out.forEach((k, v) { final d = (v is num) ? v.toDouble() : 0.0; if (d > bestV) { bestV = d; best = k; } });
      setState(() { _macResult = '$best (${bestV.toStringAsFixed(3)})'; });
    } catch (e) {
      setState(() { _macResult = 'Error: $e'; });
    }
  }

  void _startMacCamera() {
    try {
      final ed = EmotionDetection();
      final modelId = 'mobilenetv1_fer2024-11-06-08-48-50';
      ed.macShowCameraPreview(modelId: modelId);
      _macCamSub = ed.macCameraStream(modelId: modelId).listen((dist) {
        String best = '';
        double bestV = -1.0;
        dist.forEach((k, v) {
          final d = (v).toDouble();
          if (d > bestV) {
            bestV = d;
            best = k;
          }
        });
        if (mounted) {
          setState(() {
            _macResult = best.isEmpty
                ? 'No output'
                : '$best (${bestV.toStringAsFixed(3)})';
          });
        }
      });
      if (mounted) setState(() {}); // enable Stop button immediately
    } catch (e) {
      setState(() {
        _macResult = 'Camera error: $e';
      });
    }
  }

  Future<void> _stopMacCamera() async {
    await _macCamSub?.cancel();
    try { await EmotionDetection().macHideCameraPreview(); } catch (_) {}
    _macCamSub = null;
    if (mounted) setState(() {});
  }

  Widget _buildUserCodeWaiting() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_cekSecretStatus, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchingCekSecret ? null : _fetchCekSecret,
              child:
                  Text(_fetchingCekSecret ? 'Requesting...' : 'Fetch secrets'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelInit() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_initializingModels) const CircularProgressIndicator(),
            if (_initializingModels) const SizedBox(height: 12),
            Text(_modelInitStatus, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed:
                  _initializingModels ? null : () => _initializeModelsIfReady(),
              child: const Text('Retry model init'),
            ),
          ],
        ),
      ),
    );
  }
}
