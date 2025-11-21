import 'dart:async';

import 'package:camera/camera.dart';
import 'package:emotion_detection/emotion_detection.dart';
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
  String _cekSecretStatus = 'Not requested yet.';
  bool _fetchingCekSecret = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _fetchCekSecret() async {
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
    final result = await _sdkSecretModule.fetchCekSecret();
    setState(() {
      _fetchingCekSecret = false;
      if (result == null) {
        _cekSecretStatus = 'fetchCekSecret returned null (see logs).';
      } else {
        if (kDebugMode) {
          debugPrint('CEK secret response: $result');
          _cekSecretStatus = 'Success (debug): $result';
        } else {
          _cekSecretStatus = 'Success: received keys ${result.keys.join(', ')}';
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: EmotionDetectorView(controller: controller),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: _fetchingCekSecret ? null : _fetchCekSecret,
                    child: Text(
                      _fetchingCekSecret
                          ? 'Fetching SDK secret...'
                          : 'Fetch SDK CEK secret',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _cekSecretStatus,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
