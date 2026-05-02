import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:emotion_detection/emotion_detection.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load optional .env for local SDK keys (macOS/desktop-friendly)
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  // Guard camera warm-up on desktop/web to avoid MissingPluginException.
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await availableCameras();
    } catch (_) {
      // Ignore; the widget will handle camera init later.
    }
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const String _kNewOnnxModelId =
      'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx';
  String _platformVersion = 'Unknown';
  final _emotionDetectionPlugin = EmotionDetection();
  EmotionDetectorViewController controller = EmotionDetectorViewController();
  late final EmotionDetectionProvisioner _provisioner;
  static const _methodChannelName = 'face_emotion_detection';
  String _cekSecretStatus = 'Not requested yet.';
  bool _fetchingCekSecret = false;
  bool _userCodeReady = false;
  bool _modelsReady = false;
  bool _initializingModels = false;
  String _modelInitStatus = 'Waiting for user code to initialize models.';
  static const bool _kOneTimeClearCaches = true;
  bool _didClearCaches = false;
  String? _macResult;
  StreamSubscription<Map<String, double>>? _macCamSub;

  String _activeMacModelId() {
    final preferred = _provisioner.modelKey.trim();
    if (preferred.isNotEmpty) {
      return _provisioner.runtimeModelIdForKey(preferred);
    }
    final keys = _provisioner.modelKeysForPlatform(defaultTargetPlatform);
    if (keys.contains(_kNewOnnxModelId)) {
      return _provisioner.runtimeModelIdForKey(_kNewOnnxModelId);
    }
    if (keys.isNotEmpty) {
      return _provisioner.runtimeModelIdForKey(keys.first);
    }
    return _provisioner.runtimeModelIdForKey('mobilenetv1_fer');
  }

  @override
  void initState() {
    super.initState();
    // Initialize secrets module from .env or process env if present
    final env = dotenv.env;
    final procEnv = Platform.environment;
    final apiKeyId = (env['SDK_KEY_ID'] ?? procEnv['SDK_KEY_ID'] ?? '').trim();
    final apiKeySecret =
        (env['SDK_KEY_SECRET'] ?? procEnv['SDK_KEY_SECRET'] ?? '').trim();
    final baseUrl = (env['EXAMPLE_SERVER_BASE_URL'] ??
            procEnv['EXAMPLE_SERVER_BASE_URL'] ??
            '')
        .trim();
    final userName =
        (env['EXAMPLE_USER_NAME'] ?? procEnv['EXAMPLE_USER_NAME'] ?? '').trim();
    final modelKey =
        (env['EXAMPLE_MODEL_KEY'] ?? procEnv['EXAMPLE_MODEL_KEY'] ?? '').trim();
    final aadIOS = (env['EXAMPLE_MODEL_AAD_IOS'] ??
            procEnv['EXAMPLE_MODEL_AAD_IOS'] ??
            env['EXAMPLE_MODEL_AAD'] ??
            procEnv['EXAMPLE_MODEL_AAD'] ??
            '')
        .trim();
    final aad =
        (env['EXAMPLE_MODEL_AAD'] ?? procEnv['EXAMPLE_MODEL_AAD'] ?? '').trim();
    final aadAndroid = (env['EXAMPLE_MODEL_AAD_ANDROID'] ??
            procEnv['EXAMPLE_MODEL_AAD_ANDROID'] ??
            '')
        .trim();
    final aadMacOS = (env['EXAMPLE_MODEL_AAD_MACOS'] ??
            procEnv['EXAMPLE_MODEL_AAD_MACOS'] ??
            '')
        .trim();

    _provisioner = EmotionDetectionProvisioner(
      sdkKeyId: apiKeyId,
      sdkKeySecret: apiKeySecret,
      serverBaseUrl: baseUrl.isEmpty ? null : baseUrl,
      userName: userName,
      modelKey: modelKey.isEmpty ? null : modelKey,
      iosAad: aadIOS.isEmpty ? null : aadIOS,
      aad: aad.isEmpty ? null : aad,
      macosAad: aadMacOS.isEmpty ? null : aadMacOS,
      androidAad: aadAndroid.isEmpty ? null : aadAndroid,
    );

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
      final modelIds = _provisioner
          .modelKeysForPlatform(defaultTargetPlatform)
          .where((key) {
            if (defaultTargetPlatform == TargetPlatform.android &&
                (key == 'aih_fer20250115' || key == 'aih_fer')) {
              return false;
            }
            return true;
          })
          .expand((key) => _provisioner.allModelIds(key))
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
    try {
      await _provisioner.clearSecrets();
    } catch (error) {
      debugPrint('Clear cached model secrets failed: $error');
    }
  }

  Future<void> _fetchCekSecret() async {
    await _maybeClearCaches();
    if (!_provisioner.hasRequiredConfig) {
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
    String status = 'Provisioning did not complete.';
    try {
      final result = await _provisioner.provision(
        targetPlatform: defaultTargetPlatform,
        aadOverride: _provisioner.aadForPlatform(defaultTargetPlatform),
        warmUp: false,
      );
      _userCodeReady = result.isReady;
      status = result.status;
      if (_userCodeReady) {
        await _initializeModelsIfReady();
      }
    } catch (error) {
      status = 'Provisioning failed: $error';
      _userCodeReady = false;
      _modelsReady = false;
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
          title: Text('Emotion SDK Example ($_platformVersion)'),
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
                  ? 'Select an image or start camera to run the model.'
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
                  onPressed: _userCodeReady && _macCamSub == null
                      ? _startMacCamera
                      : null,
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
      final typeGroup =
          const XTypeGroup(label: 'images', extensions: ['png', 'jpg', 'jpeg']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      _ensureModelRuntimeChannel();
      final modelId = _activeMacModelId();
      final out = await ModelRuntime.predict(modelId, {'imageBytes': bytes});
      if (out.isEmpty) {
        setState(() {
          _macResult = 'No output';
        });
        return;
      }
      // Find top label
      String best = '';
      double bestV = -1.0;
      out.forEach((k, v) {
        final d = (v is num) ? v.toDouble() : 0.0;
        if (d > bestV) {
          bestV = d;
          best = k;
        }
      });
      setState(() {
        _macResult = '$best (${bestV.toStringAsFixed(3)})';
      });
    } catch (e) {
      setState(() {
        _macResult = 'Error: $e';
      });
    }
  }

  void _startMacCamera() {
    try {
      final ed = EmotionDetection();
      final modelId = _activeMacModelId();
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
    try {
      await EmotionDetection().macHideCameraPreview();
    } catch (_) {}
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
