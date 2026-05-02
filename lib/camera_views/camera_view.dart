import 'dart:io';

import 'package:emotion_detection/extension/context_extensions.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:path_provider/path_provider.dart';

typedef OnSwitchCamera = void Function();
typedef OnRecord = void Function();
typedef OnTakePhoto = void Function();

class CameraViewController extends ChangeNotifier {
  Future<String>? Function()? _takePicture;

  Future<String>? takePicture() => _takePicture?.call();

  void _attach({Future<String>? Function()? takePicture}) {
    _takePicture = takePicture;
  }

  void _detach() {
    _takePicture = null;
  }
}

class CameraView extends StatefulWidget {
  // Stores state for the legacy widget-level switchCamera method.
  // ignore: prefer_const_constructors_in_immutables
  CameraView({
    super.key,
    required this.cameraViewController,
    required this.customPaint,
    required this.onImage,
    required this.onSnapShot,
    this.onCameraFeedReady,
    this.onDetectorViewModeChanged,
    this.onCameraLensDirectionChanged,
    this.initialCameraLensDirection = CameraLensDirection.back,
    this.showOpenImageButton = false,
    this.showExposure = true,
    this.showZoom = false,
    this.showImageOpen = false,
    this.showTitle = false,
    this.title,
    this.showSelectCameraButton = false,
    this.showTakePhotoButton = false,
  });

  final CustomPaint? customPaint;
  final Function(InputImage inputImage) onImage;
  final VoidCallback? onCameraFeedReady;
  final VoidCallback? onDetectorViewModeChanged;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;
  final VoidCallback onSnapShot;
  final String? title;
  final bool showOpenImageButton;
  final bool showExposure;
  final bool showZoom;
  final bool showImageOpen;
  final bool showTitle;
  final bool showSelectCameraButton;
  late final _CameraViewState _myState;
  final bool showTakePhotoButton;

  final CameraViewController cameraViewController;

  @override
  // ignore: no_logic_in_create_state
  State<CameraView> createState() {
    _myState = _CameraViewState();
    return _myState;
  }

  void takePhoto() {}

  Future switchCamera() async {
    await _myState._switchLiveCamera();
  }
}

class _CameraViewState extends State<CameraView> {
  static List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = -1;
  double _currentZoomLevel = 1.0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;
  bool _changingCameraLens = false;
  String? title;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    title = widget.title;
    widget.cameraViewController._attach(
      takePicture: _takePicture,
    );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      for (var i = 0; i < _cameras.length; i++) {
        if (_cameras[i].lensDirection == widget.initialCameraLensDirection) {
          _cameraIndex = i;
          break;
        }
      }
      if (_cameraIndex == -1 && _cameras.isNotEmpty) {
        _cameraIndex = 0;
      }
      if (_cameraIndex == -1) {
        _setCameraError('No camera available on this device.');
        return;
      }
      await _startLiveFeed();
    } on CameraException catch (error, stackTrace) {
      _recordCameraException('availableCameras', error, stackTrace);
    } catch (error) {
      _setCameraError('Camera init failed: $error');
    }
  }

  Future<String>? _takePicture() async {
    if (_controller == null) return "";
    try {
      final file = await _controller?.takePicture();
      if (file == null) return "";
      final appDir = await getApplicationDocumentsDirectory();
      final savedPath = "${appDir.path}/${DateTime.now().microsecond}.jpg";
      await File(file.path).copy(savedPath);
      return file.path;
    } catch (e) {
      debugPrint("take picture failed");
      return "";
    }
  }

  void setTitle(String newTitleText) {
    setState(() {
      title = newTitleText;
    });
  }

  @override
  void dispose() {
    _stopLiveFeed();
    widget.cameraViewController._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //final viewModel = Provider.of<ViewModel>(context);
    //title = "Emotion"; //viewModel.detectedEmotion;

    return Scaffold(body: _liveFeedBody());
  }

  Widget _liveFeedBody() {
    if (_cameraError != null) return _cameraErrorBody(_cameraError!);
    if (_cameras.isEmpty) return Container();
    if (_controller == null) return Container();
    if (_controller?.value.isInitialized == false) return Container();
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: _changingCameraLens
                ? const Center(
                    child: Text('Changing camera lens'),
                  )
                : CameraPreview(
                    _controller!,
                    child: widget.customPaint,
                  ),
          ),
          //_backButton(),
          if (widget.showSelectCameraButton) _switchLiveCameraToggle(),
          if (widget.showOpenImageButton) _detectionViewModeToggle(),
          if (widget.showZoom) _zoomControl(),
          if (widget.showExposure) _exposureControl(),
          if (widget.showTitle && title != null)
            Positioned(
                top: 200,
                left: 150,
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    widget.title!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        fontFamily: 'Inter'),
                  )
                ])),
          if (widget.showTakePhotoButton) _takePhotoButton(),
        ],
      ),
    );
  }

  Widget _cameraErrorBody(String message) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            message,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _detectionViewModeToggle() => Positioned(
        bottom: 20,
        left: 8,
        child: SizedBox(
          height: 50.0,
          width: 50.0,
          child: FloatingActionButton(
            heroTag: Object(),
            onPressed: widget.onDetectorViewModeChanged,
            backgroundColor: Colors.black54,
            child: const Icon(
              Icons.photo_library_outlined,
              size: 25,
              color: Colors.white,
            ),
          ),
        ),
      );

  Widget _takePhotoButton() => Positioned(
        bottom: 20,
        left: context.width / 2 - 50,
        child: SizedBox(
          height: 50.0,
          width: 50.0,
          child: FloatingActionButton(
            heroTag: Object(),
            onPressed: widget.onSnapShot,
            backgroundColor: Colors.black54,
            child: const Icon(
              Icons.fiber_manual_record_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
      );

  Widget _switchLiveCameraToggle() => Positioned(
        bottom: 20,
        right: 8,
        child: SizedBox(
          height: 50.0,
          width: 50.0,
          child: FloatingActionButton(
            heroTag: Object(),
            onPressed: _switchLiveCamera,
            backgroundColor: Colors.black54,
            child: Icon(
              Platform.isIOS
                  ? Icons.flip_camera_ios_outlined
                  : Icons.flip_camera_android_outlined,
              size: 25,
              color: Colors.white,
            ),
          ),
        ),
      );

  Widget _zoomControl() => Positioned(
        bottom: 16,
        left: 0,
        right: 0,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 250,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Slider(
                    value: _currentZoomLevel,
                    min: _minAvailableZoom,
                    max: _maxAvailableZoom,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChanged: (value) async {
                      setState(() {
                        _currentZoomLevel = value;
                      });
                      await _controller?.setZoomLevel(value);
                    },
                  ),
                ),
                Container(
                  width: 50,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: Text(
                        '${_currentZoomLevel.toStringAsFixed(1)}x',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _exposureControl() => Positioned(
        top: 40,
        right: 8,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 250,
          ),
          child: Column(children: [
            Container(
              width: 55,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: Text(
                    '${_currentExposureOffset.toStringAsFixed(1)}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SizedBox(
                  height: 30,
                  child: Slider(
                    value: _currentExposureOffset,
                    min: _minAvailableExposureOffset,
                    max: _maxAvailableExposureOffset,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChanged: (value) async {
                      setState(() {
                        _currentExposureOffset = value;
                      });
                      await _controller?.setExposureOffset(value);
                    },
                  ),
                ),
              ),
            ),
            const Icon(Icons.exposure)
          ]),
        ),
      );

  Future<void> _startLiveFeed() async {
    final camera = _cameras[_cameraIndex];
    final controller = CameraController(
      camera,
      // Set to ResolutionPreset.high. Do NOT set it to ResolutionPreset.max because for some phones does NOT work.
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) {
        return;
      }
      _currentZoomLevel = await controller.getMinZoomLevel();
      _minAvailableZoom = _currentZoomLevel;
      _maxAvailableZoom = await controller.getMaxZoomLevel();
      _currentExposureOffset = 0.0;
      _minAvailableExposureOffset = await controller.getMinExposureOffset();
      _maxAvailableExposureOffset = await controller.getMaxExposureOffset();
      await controller.startImageStream(_processCameraImage);
      _cameraError = null;
      if (widget.onCameraFeedReady != null) {
        widget.onCameraFeedReady!();
      }
      if (widget.onCameraLensDirectionChanged != null) {
        widget.onCameraLensDirectionChanged!(camera.lensDirection);
      }
      setState(() {});
    } on CameraException catch (error, stackTrace) {
      await _stopLiveFeed();
      _recordCameraException(
        'startLiveFeed(${camera.lensDirection.name})',
        error,
        stackTrace,
      );
    }
  }

  Future _stopLiveFeed() async {
    final c = _controller;
    if (c != null) {
      try {
        if (c.value.isInitialized && c.value.isStreamingImages) {
          await c.stopImageStream();
        }
      } catch (_) {
        // swallow errors from stopping uninitialized or already-stopped streams
      }
      try {
        await c.dispose();
      } catch (_) {}
      _controller = null;
    }
  }

  Future _switchLiveCamera() async {
    if (_cameras.length <= 1) {
      return;
    }
    setState(() => _changingCameraLens = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;

    await _stopLiveFeed();
    await _startLiveFeed();
    setState(() => _changingCameraLens = false);
  }

  void _recordCameraException(
    String phase,
    CameraException error,
    StackTrace stackTrace,
  ) {
    final description = error.description?.trim();
    final message = description == null || description.isEmpty
        ? 'Camera error (${error.code}) during $phase.'
        : 'Camera error (${error.code}) during $phase: $description';
    debugPrint(message);
    debugPrintStack(stackTrace: stackTrace);
    _setCameraError(message);
  }

  void _setCameraError(String message) {
    if (!mounted) {
      _cameraError = message;
      return;
    }
    setState(() {
      _cameraError = message;
    });
  }

  void _processCameraImage(CameraImage image) {
    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;
    widget.onImage(inputImage);
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    // print(
    //     'lensDirection: ${camera.lensDirection}, sensorOrientation: $sensorOrientation, ${_controller?.value.deviceOrientation} ${_controller?.value.lockedCaptureOrientation} ${_controller?.value.isCaptureOrientationLocked}');
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      // print('rotationCompensation: $rotationCompensation');
    }
    if (rotation == null) return null;
    // print('final rotation: $rotation');

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // validate format depending on platform
    // only supported formats:
    // * nv21 for Android
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    // since format is constraint to nv21 or bgra8888, both only have one plane
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: plane.bytesPerRow, // used only in iOS
      ),
    );
  }
}
