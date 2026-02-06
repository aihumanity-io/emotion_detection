//import 'package:aih_app/extension/context_extensions.dart';
import 'package:emotion_detection/extension/context_extensions.dart';
import 'package:emotion_detection/native/emotion_detection.dart';
import 'package:emotion_detection/utility/utility.dart';
//import 'package:aih_app/utility/utility.dart';
import 'package:camera/camera.dart';
//import 'package:face_expression_package/face_expression_package.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as imagelib;
//import 'package:provider/provider.dart';

import '../constants/emotion_enum.dart';
//import '../models/model.dart';
import './camera_views/detector_view.dart';
import './camera_views/painters/face_detector_painter.dart';
import 'EmotionDisplayScreen.dart';

typedef OnFaceImage = Image Function(List<imagelib.Image>? images);
typedef OnEmotion = Function(Map<String, double> emotions);
typedef OnImage = Function(imagelib.Image? image);

class EmotionDetectorViewController extends ChangeNotifier {
  VoidCallback? _takeSnapShot;
  void takeSnapShot() => _takeSnapShot?.call();

  Future<String>? Function()? _takePicture;
  Future<String>? takePicture() => _takePicture?.call();

  void _attach(
      {Future<String>? Function()? takePicture, VoidCallback? takeSnapShot}) {
    _takePicture = takePicture;
    _takeSnapShot = takeSnapShot;
  }

  void _detach() {
    _takePicture = null;
    _takeSnapShot = null;
  }
}

class EmotionDetectorView extends StatefulWidget {
  EmotionDetectorView(
      {Key? key,
      required this.controller,
      this.onFaceImage,
      this.onEmotion,
      this.onImage})
      : super(key: key) {}

  final EmotionDetectorViewController controller;
  OnFaceImage? onFaceImage;
  OnEmotion? onEmotion;
  OnImage? onImage;

  @override
  State<EmotionDetectorView> createState() => _FaceDetectorViewState();
}

class _FaceDetectorViewState extends State<EmotionDetectorView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
    ),
  );
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  var _cameraLensDirection = CameraLensDirection.front;
  List<Rect>? faceData;

  String emotion = EmotionEnum.NEUTRAL.value;
  Rect? faceRect;
  //imagelib.Image? faceImage;
  bool snapShotNow = false;
  imagelib.Image? snapShotFrame;
  bool snapShotProcessed = false;

  EmotionDetectionController emotionController = EmotionDetectionController();
  DetectorViewController detectorViewController = DetectorViewController();

  @override
  void initState() {
    super.initState();
    widget.controller._attach(
      takePicture: detectorViewController.takePicture,
      takeSnapShot: _onSnapShot,
    );
  }

  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    widget.controller._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      DetectorView(
        detectorViewController: detectorViewController,
        title: 'Model Test',
        customPaint: _customPaint,
        text: _text,
        onImage: _processImage,
        onSnapShot: _onSnapShot,
        initialCameraLensDirection: _cameraLensDirection,
        onCameraLensDirectionChanged: (value) => _cameraLensDirection = value,
      ),
      Positioned(
          top: 200,
          left: context.width / 2.0 - 50,
          child: Center(
            child: Text(
              _text ?? 'Unknown',
              style: TextStyle(color: Colors.white),
            ),
          )),
    ]);
  }

  void _onSnapShot() async {
    snapShotNow = true;
    snapShotProcessed = false;
    // await Navigator.of(context).push(
    //   MaterialPageRoute(
    //     builder: (context) => EmotionDisplayScreen(image: snapShotFrame!),
    //   ),
    // );
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (snapShotNow && !snapShotProcessed) {
      snapShotFrame = convertNV21(
          inputImage.bytes!,
          inputImage.metadata!.size.width.toInt(),
          inputImage.metadata!.size.height.toInt());
      ;
    }
    if (widget.onImage != null) {
      widget.onImage!(snapShotFrame);
    }
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    if (!snapShotNow || !snapShotProcessed) {
      await processFaceImage(inputImage);
    }
    if (snapShotNow) {
      snapShotProcessed = true;
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<dynamic> processFaceImage(InputImage inputImage) async {
    final int startT = DateTime.timestamp().millisecondsSinceEpoch;
    final faces = await _faceDetector.processImage(inputImage);
    print(
        "Face detection model time: ${DateTime.timestamp().millisecondsSinceEpoch - startT} ms");
    Map? emotionMap = await emotionController.processImage(inputImage, faces);
    emotion = emotionController.getEmotionString(emotionMap);
    print('emotion returns: $emotion');

    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      final painter = FaceDetectorPainter(
        faces,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
        _cameraLensDirection,
      );
      _customPaint = CustomPaint(painter: painter);
    } else {
      String text = 'Faces found: ${faces.length}\n\n';
      for (final face in faces) {
        text += 'face: ${face.boundingBox}\n\n';
      }
      //_text = text;
      // TODO: set _customPaint to draw boundingRect on top of image
      _customPaint = null;
    }
    if (emotion != EmotionEnum.NEUTRAL.value) {
      _text = emotion;
      print("set emotion string: $emotion");
    }
    if (widget.onFaceImage != null) {
      widget.onFaceImage!(faceImages(inputImage, faces));
    }
    if (widget.onEmotion != null && emotionMap != null) {
      try {
        final Map<String, double> dist = emotionMap.map((k, v) {
          final key = k?.toString() ?? '';
          final numVal = (v is num) ? v : 0.0;
          return MapEntry(key, numVal.toDouble());
        }).cast<String, double>();
        widget.onEmotion!(dist);
      } catch (_) {
        // Fallback: ignore malformed map
      }
    }
  }

  List<imagelib.Image> faceImages(InputImage image, List<Face> faces) {
    List<imagelib.Image> faceImages = [];

    for (Face face in faces) {
      //if (faces.isNotEmpty) {
      //faceData = await emotionDetectionController.processImage(inputImage.bytes!, inputImage.metadata!.size);
      final nv21Image = convertNV21(
          image.bytes!,
          image.metadata!.size.width.toInt(),
          image.metadata!.size.height.toInt());
      //final maxBoxIndex = findLargestBoundingBoxIndex(faces);
      //print("maxFaceIndex: $maxBoxIndex");
      faceRect = face.boundingBox;

      final faceImage = imagelib.copyCrop(
        nv21Image,
        x: faceRect!.left.toInt(),
        y: faceRect!.top.toInt(),
        width: faceRect!.width.toInt(),
        height: faceRect!.height.toInt(),
      );
      faceImages.add(faceImage);
    }
    return faceImages;
  }

  imagelib.Image? faceImage(InputImage image, List<Face> faces) {
    if (faces.isNotEmpty) {
      final nv21Image = convertNV21(
          image.bytes!,
          image.metadata!.size.width.toInt(),
          image.metadata!.size.height.toInt());
      final maxBoxIndex = findLargestBoundingBoxIndex(faces);
      print("maxFaceIndex: $maxBoxIndex");
      faceRect = faces[maxBoxIndex].boundingBox;

      final faceImage = imagelib.copyCrop(
        nv21Image,
        x: faceRect!.left.toInt(),
        y: faceRect!.top.toInt(),
        width: faceRect!.width.toInt(),
        height: faceRect!.height.toInt(),
      );
      return faceImage;
    }
    return null;
  }
}
